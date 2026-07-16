--- Acceptance suite for the Java basic service archetype: renders the archetype, verifies the
--- layout, builds the Maven reactor, boots the Spring Boot service, and proves its single stub route
--- and actuator health both answer. This suite defines the archetype's acceptance bar.
---
--- Run from the archetype repo root (uses ./prova.toml):   prova
--- requires archetect + mvn + java (JDK 21); skips cleanly without them. No database: a basic service
--- weaves in no resources, so there is nothing to provision.
---
--- Rendering shells out to the `archetect` CLI (one fresh process per render) rather than the
--- in-process `archetect.render`, which can only render once per process.

local SRC         = "."   -- shell.run inherits prova's cwd (the repo root), where the archetype lives
local PROJECT_DIR = "example-service"
local BOOT_JAR    = "example-service-server/target/example-service-server-1.0.0-SNAPSHOT.jar"

local function answers_yaml()
  return table.concat({
    'author_name: "Test Author"',
    'author_email: "test@example.com"',
    'org_name: "acme"',
    'solution_name: "platform"',
    'prefix_name: "Example"',
    'suffix_name: "Service"',
    'group_id: "acme.platform"',
    'artifactory_host: "acme.jfrog.io"',
    'image_registry: "ghcr.io/acme"',
  }, "\n") .. "\n"
end

local function render(ctx)
  local out     = ctx:tempdir()
  local answers = out .. "/answers.yaml"
  fs.write(answers, answers_yaml())
  shell.run("archetect render " .. SRC .. " " .. out .. "/rendered -A " .. answers .. " -D --headless",
    { timeout = "180s", check = true })
  return out .. "/rendered/" .. PROJECT_DIR
end

-- Build the reactor, then repackage the server into a runnable boot jar (see the REST suite's notes
-- on why install alone is a thin jar).
local function build(root)
  shell.run("mvn -q -B -DskipTests install", { cwd = root, timeout = "900s", check = true })
  shell.run("mvn -q -B -o -pl example-service-server -DskipTests package spring-boot:repackage",
    { cwd = root, timeout = "900s", check = true })
end

local EXPECTED_FILES = {
  "pom.xml",
  "example-service-bom/pom.xml",
  "example-service-core/pom.xml",
  "example-service-core/src/main/java/acme/platform/example/core/CoreConfig.java",
  "example-service-server/pom.xml",
  "example-service-server/src/main/java/acme/platform/example/server/Application.java",
  "example-service-server/src/main/java/acme/platform/example/server/RootController.java",
  "example-service-server/src/main/resources/application.yaml",
  "example-service-integration-tests/pom.xml",
  ".github/workflows/build.yaml",
}

local project = prova.fixture("java-basic:project", Scope.File, function(ctx)
  return render(ctx)
end)

prova.group("java-basic", { requires = { "archetect" } }, function(g)
  g:test("layout", function(t)
    local root = t:use(project)
    t:expect_all(function()
      for _, f in ipairs(EXPECTED_FILES) do
        t:expect(fs.exists(root .. "/" .. f), f):is_true()
      end
    end)
  end)

  g:test("platform kubernetes manifests parse", function(t)
    local root = t:use(project)
    local matches = fs.glob(root, ".platform/kubernetes/**/*.yaml")
    t:expect(#matches, "kubernetes manifests"):never():equals(0)
    for _, path in ipairs(matches) do
      yaml.parse_all(fs.read(path))
    end
  end)
end)

local service = prova.fixture("java-basic:service", Scope.File, function(ctx)
  local root = ctx:use(project)
  build(root)

  local port, mgmt = net.free_port(), net.free_port()
  ctx:manage(shell.spawn("java -jar " .. BOOT_JAR, {
    cwd = root,
    env = { SERVER_PORT = tostring(port), MANAGEMENT_PORT = tostring(mgmt) },
  }))

  local readiness = "http://127.0.0.1:" .. mgmt .. "/health/readiness"
  http.wait_for(readiness, { status = 200, timeout = "180s", every = "1s" })
  return { readiness = readiness, base = "http://127.0.0.1:" .. port }
end)

prova.group("java-basic boots", { requires = { "archetect", "mvn", "java" } }, function(g)
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
