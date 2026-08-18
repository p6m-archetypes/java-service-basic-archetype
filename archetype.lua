local context = Context.new()

-- Identity (S1). One library, one implementation: p6m-identity asks for the project name and
-- the solution slug.
-- It replaces the author x org x project composition — nothing rendered here read the author, and
-- org_name x solution_name were two prompts building one string. `repo_name` and `github_owner`
-- are derived inside the library, never asked.
-- `entity = false`: this shape generates no domain code, so a CRUD entity would be a
-- prompt whose answer nothing reads (S1b / E2).
local identity = require("p6m-identity")
identity.prompt(context, { entity = false })

-- Java-specific identity
--
-- Normalize an input into a valid lowercase Java package segment.
local function pkg_segment(value)
    return string.lower((string.gsub(tostring(value), "[^%w]", "")))
end

-- groupId is the shared Maven coordinate for the whole solution. Asked OPTIONAL and derived
-- after: a default computed from `solution_name` cannot be known until that prompt is answered,
-- so an interface probe resolves it against a placeholder and ships that to every client. The
-- help states the derivation instead of interpolating a value into it.
context:prompt_text("Maven Group ID:", "group_id", {
    optional    = true,
    placeholder = "acme.payments",
    help        = "Maven groupId shared across the solution. Leave blank to use the solution slug "
        .. "with its separator swapped (acme-payments -> acme.payments).",
})
if context:get("group_id") == nil or context:get("group_id") == "" then
    context:set("group_id", (string.gsub(context:get("solution-name"), "%-", ".")))
end

context:prompt_text("Artifactory Host:", "artifactory_host", {
    placeholder = "your-org.jfrog.io",
    help = "JFrog Artifactory hostname for Maven repository",
})

-- Derived keys
-- root_package is named after the PROJECT, not the entity: it is where this application's code
-- lives, so it must not move when someone answers a different `entity_name`. (It used to be built
-- from `prefix_name`, back when one answer was doing both jobs.)
context:set("root_package", context:get("group_id") .. "." .. pkg_segment(context:get("project-name")))
context:set("root_directory", (string.gsub(context:get("root_package"), "%.", "/")))

-- Service configuration
-- `debug` is not asked: nothing any archetype renders reads `debug_port` (measured
-- fleet-wide 2026-08-18) — a prompt whose answer nothing consumes cannot justify itself
-- (S1b / E2). Re-add it here if a Dockerfile or manifest ever publishes the port.
require("ports").prompt(context, { ports = { { "service", help = "HTTP port for the service" }, "management" } })

-- EditorConfig + gitignore
local editor_config = require("editor-config")
editor_config.prompt(context, {
    languages     = { "Java", "YAML", "Markdown" },
    gitattributes = true,
})

local gitignore = require("gitignore")
gitignore.prompt(context, {
    ignores = { "Java", "Claude", "IDEA", "VSCode", "macOS" },
})

-- SCM
local scm = require("scm")
scm.prompt(context)

if archetype.switches.is_enabled("debug-context") then
    log.info(archetype.description .. " Context:")
    output.print(format.yaml(context))
end

-- Render base workspace
directory.render("contents/base", context)

local dest = { destination = context:get("project-name") }

-- CI workflows
local ci = require("java-ci")
ci.render(context, dest)

-- Platform manifests
-- A basic service weaves in no resources; pre-set these so the manifests library
-- omits resourceRequirements and does not prompt for them.
context:set("persistence", "None")
context:set("cache", "None")
context:set("messaging", "None")
context:set("messaging_access", "produce")
context:set("protocol", "REST")
local platform = require("platform-application-manifests")
platform.prompt(context)
platform.finalize(context, dest)

-- EditorConfig, gitignore, SCM finalize
editor_config.finalize(context, dest)
gitignore.finalize(context, dest)
scm.finalize(context)

-- Archive (zip / tarball switches for Ybor Studio)
require("archiver").finalize(context)

return context
