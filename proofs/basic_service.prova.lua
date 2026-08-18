--- Acceptance suite for the Java basic service archetype: renders the archetype, verifies the
--- layout, builds the Maven reactor, boots the Spring Boot service, and proves its single stub route
--- and actuator health both answer. This suite defines the archetype's acceptance bar.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova
--- requires mvn + java (JDK 21); skips cleanly without them. No database: a basic service weaves in
--- no resources, so there is nothing to provision.

local SRC = "."
local BOOT_JAR = "example-service-server/target/example-service-server-1.0.0-SNAPSHOT.jar"

local ANSWERS = {
  project_name = "example-service",
  solution_name = "acme-platform",
  entity_name = "example",
  group_id         = "acme.platform",
  artifactory_host = "acme.jfrog.io",
  image_registry   = "ghcr.io/acme",
}

local EXPECTED_FILES = {
  "pom.xml",
  "example-service-bom/pom.xml",
  "example-service-core/pom.xml",
  "example-service-core/src/main/java/acme/platform/exampleservice/core/CoreConfig.java",
  "example-service-server/pom.xml",
  "example-service-server/src/main/java/acme/platform/exampleservice/server/Application.java",
  "example-service-server/src/main/java/acme/platform/exampleservice/server/RootController.java",
  "example-service-server/src/main/resources/application.yaml",
  "example-service-integration-tests/pom.xml",
  ".github/workflows/build.yaml",
}

-- Build the reactor, then repackage the server into a runnable boot jar (see the REST suite's notes
-- on why install alone is a thin jar).
local function build(dir)
  shell.run("mvn -q -B -DskipTests install", { cwd = dir, timeout = "900s", check = true })
  shell.run("mvn -q -B -nsu -pl example-service-server -DskipTests package spring-boot:repackage",
    { cwd = dir, timeout = "900s", check = true })
end

local project = prova.fixture("java-basic:project", Scope.File, function(ctx)
  return archetect.render{ source = SRC, answers = ANSWERS, destination = ctx:tempdir("render1"), defaults = true }
end)

archetect.verify(project, {
  name = "java-basic",
  project_dir = "example-service",
  expected_files = EXPECTED_FILES,
  yaml_globs = { ".platform/kubernetes/**/*.yaml" },
})

local service = prova.fixture("java-basic:service", Scope.File, function(ctx)
  local root = ctx:use(project):dir("example-service")
  build(root.path)

  local port, mgmt = net.free_port(), net.free_port()
  ctx:manage(shell.spawn("java -jar " .. BOOT_JAR, {
    cwd = root.path,
    env = { SERVER_PORT = port, MANAGEMENT_PORT = mgmt },
  }))

  local readiness = "http://127.0.0.1:" .. mgmt .. "/health/readiness"
  http.wait_for(readiness, { status = 200, timeout = "180s", every = "1s" })
  return { readiness = readiness, base = "http://127.0.0.1:" .. port }
end)

prova.group("java-basic boots", { requires = { "mvn", "java" } }, function(g)
  g:test("readiness reports UP", function(t)
    local svc = t:use(service)
    local res = http.get(svc.readiness)
    t:expect(res.status):equals(200)
    t:expect(res:json().status):equals("UP")
  end)

  g:test("the stub root route identifies the service", function(t)
    local svc = t:use(service)
    local res = http.get(svc.base .. "/")
    t:expect(res.status):equals(200)
    local body = res:json()
    t:expect(body.service):equals("example-service")
    t:expect(body.status):equals("ok")
  end)
end)
