--- The p6m platform standards, held against the java BASIC service archetype.
---
--- A basic service is its own SHAPE: it generates a bootable, 12-factor service with no domain, so
--- S2 (the CRUD API) has no subject here while S3-S9 apply in full. `p6m.spec{ shape = "basic" }`
--- says that in one place — it asks for no entity, and the oracle is told the shape has none rather
--- than left to guess a name it deliberately does not derive (S1).
---
--- Container-first (S8b): the SUT is the archetype's own .platform/docker/prd image on a topology
--- network. Docker is the single requirement — no JDK or Maven on the host, so this suite behaves
--- identically on a laptop and on a CI runner. No database: a basic service weaves in no
--- resources, so there is nothing to provision and `p6m.sut` takes no `db`.

local p6m = require("p6m")

-- Two name shapes on purpose: a single word and a multi-word, because casing bugs only show on
-- the second. No persistence axis — this shape has none.
local NAME_SHAPES = { "customer-service", "user-details-service" }

for _, project in ipairs(NAME_SHAPES) do
  local spec = p6m.spec{
    language = "java", shape = "basic",
    project = project, solution = "acme-platform", registry = "ghcr.io/acme",
    answers = { group_id = "acme.platform", artifactory_host = "acme.jfrog.io" },
  }

  local project_fixture = p6m.render(spec)

  local sut = prova.topology(spec.label .. ":sut", function(ctx)
    local root = ctx:use(project_fixture):dir(spec.project_dir)
    return p6m.sut(ctx, { root = root.path, id = spec.id, transport = "rest" })
  end)

  prova.group(spec.label, { requires = { "docker" }, tags = { "standards" } }, function(g)
    -- S3-S7: the platform env contract honored, health on the management port, real Prometheus
    -- metrics, structured logs read from the flag rather than merely defined.
    p6m.standards.runtime(g, sut)
  end)
end

-- S1b: the archetype's own prompt surface is the declared interface. A defaults=false render
-- proves nothing beyond the declared key is REQUIRED; the composed catalog proves no vestigial
-- DEFAULTED prompt survives — including an entity prompt, which this shape must not ask for.
-- Hermetic; no docker.
local archetype_spec = p6m.spec{
  language = "java", shape = "basic",
  project = "billing-service", solution = "acme-platform", registry = "ghcr.io/acme",
  answers = { group_id = "acme.platform", artifactory_host = "acme.jfrog.io" },
}

prova.group("java-basic: the archetype itself", function(g)
  p6m.standards.prompt_surface(g, archetype_spec, { resources = { "java-resource-postgresql", "java-resource-mysql", "java-resource-redis", "java-resource-kafka", "java-resource-pulsar", "java-resource-s3", "java-resource-azure-blob" } })
end)

-- CI parity (S10): the rendered project's own build workflow path on a fresh clone, in the
-- toolchain image. The Dockerfile and CI are two independent build paths; S10 holds the second.
prova.group(archetype_spec.label .. ":ci", { requires = { "docker" }, tags = { "standards" } }, function(g)
  p6m.standards.ci_parity(g, p6m.render(archetype_spec), {
    stack = "java",
    project_dir = archetype_spec.project_dir,
    name = "java-basic",
  })
end)

-- E7's released-tag bar, as the `p6m-pin` reminder: DUE while the manifest pins `dev` (the
-- YP6M-3372 staging window), silent again once the pin returns to a released tag.
p6m.pin_reminder()
