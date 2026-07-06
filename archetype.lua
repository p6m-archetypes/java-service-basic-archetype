local context = Context.new()

-- Identity
require("author").prompt(context)
require("org").prompt(context)

context:set("suffix_options", { "Service", "Orchestrator", "Adapter", "Router", "Gateway" })
context:set("suffix_default", "Service")
require("project").prompt(context)

context:set("repo_name", context:get("project-name"))
context:set("github_owner", context:get("org-solution-name"))

-- Java-specific identity
--
-- Normalize an input into a valid lowercase Java package segment.
local function pkg_segment(value)
    return string.lower((string.gsub(tostring(value), "[^%w]", "")))
end

-- groupId is the shared Maven coordinate for the whole solution (org.solution).
local group_id_default = pkg_segment(context:get("org_name")) .. "." .. pkg_segment(context:get("solution_name"))
context:prompt_text("Maven Group ID:", "group_id", {
    default = group_id_default,
    help = "Maven groupId shared across the solution (e.g. " .. group_id_default .. ")",
})

context:prompt_text("Artifactory Host:", "artifactory_host", {
    placeholder = "your-org.jfrog.io",
    help = "JFrog Artifactory hostname for Maven repository",
})

-- Derived keys
-- root_package adds the project prefix so each application owns its own package
-- namespace under the shared solution groupId (e.g. org.solution.prefix).
context:set("root_package", context:get("group_id") .. "." .. pkg_segment(context:get("prefix-name")))
context:set("project_title", context:get("PrefixName") .. " " .. context:get("SuffixName"))
context:set("root_directory", (string.gsub(context:get("root_package"), "%.", "/")))

-- Service configuration
require("ports").prompt(context, { ports = { { "service", help = "HTTP port for the service" }, "management", "debug" } })

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
