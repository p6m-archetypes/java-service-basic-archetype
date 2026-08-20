local context = Context.new()

-- The prompt surface is laid out in PAGES and SECTIONS. These carry the author's grouping intent —
-- the one thing a derived interface cannot infer from the script — to every renderer: a wizard step
-- in Ybor Studio, a titled heading in the terminal, a block comment in an answers template.
--
-- Built for the HYBRID drive: a client describes with the answers it has, renders the first page
-- that still has children, collects them, and describes again. Two consequences shape what is
-- written here:
--
--   * Keys are PINNED, never derived from a title, because a wizard routes on them and pages
--     appear and disappear between rounds. Titles are display text; keys are identity.
--   * A prompt that depends on an earlier answer sits in the SAME page as what it depends on
--     (Messaging Access under Messaging, repository details under Source Control). The page comes
--     back with new fields and the client stays on that step — progressive disclosure, rather than
--     a step that vanishes and reappears elsewhere.
--
-- The vocabulary is the fleet's, not this archetype's: every p6m archetype uses the same page and
-- section keys, so a form reads identically whatever the language or shape. An archetype omits a
-- section it has no prompts for; it does not invent one.
local identity = require("p6m-identity")

context:page({ title = "Project", key = "project",
               help = "What this service is called, and the domain it models." }, function(ctx)
    identity.prompt_project(ctx, { entity = false })

    -- The deployment coordinates, grouped deliberately: this is exactly the set Ybor Studio
    -- supplies per solution, so hiding them later is "this section came back empty" rather than a
    -- re-grouping exercise.
    ctx:section({ title = "Platform", key = "platform",
                  help = "Where this service deploys and publishes." }, function(ctx)
        identity.prompt_solution(ctx)

        -- The registry is asked here rather than by `platform.prompt()` below: the manifests
        -- library runs last (it needs the resource selections), which would put the registry dead
        -- last in the derived interface. The library still owns the prompt definition.
        require("platform-application-manifests").prompt_registry(ctx)

        -- Asked OPTIONAL and derived after: an envelope computed from `solution_name` cannot be
        -- known until that prompt is answered, so a probe would resolve it against a placeholder.
        ctx:prompt_text("Maven Group ID:", "group_id", {
            optional    = true,
            placeholder = "acme.payments",
            help        = "Maven groupId shared across the solution. Leave blank to use the "
                .. "solution slug with its separator swapped (acme-payments -> acme.payments).",
        })
        if ctx:get("group_id") == nil or ctx:get("group_id") == "" then
            ctx:set("group_id", (string.gsub(ctx:get("solution-name"), "%-", ".")))
        end

        -- OPTIONAL, deliberately. This was the one prompt a first-time user could not answer:
        -- a registry hostname nobody outside the owning org knows, with no default, blocking the
        -- form. A scaffold has no business requiring a package registry to exist — so when it is
        -- absent the pom simply omits its distributionManagement, and `mvn deploy` is a thing you
        -- configure when you have somewhere to deploy to. Ybor Studio supplies it per solution
        -- (see p6m-catalog's README), which is where a company-specific hostname belongs.
        ctx:prompt_text("Artifactory Host:", "artifactory_host", {
            optional    = true,
            placeholder = "your-org.jfrog.io",
            help        = "JFrog Artifactory hostname for the Maven repository. Leave blank to "
                .. "omit publishing configuration from the pom.",
        })
    end)

    ctx:section({ title = "Service", key = "service",
                  help = "The ports this service listens on." }, function(ctx)
        -- `debug` is not asked: nothing this archetype renders reads `debug_port` (S1b / E2).
        require("ports").prompt(ctx, { ports = { "service", "management" } })
    end)
end)

-- Derived keys. Not prompts, so they sit outside the layout.
--
-- Normalize an input into a valid lowercase Java package segment.
local function pkg_segment(value)
    return string.lower((string.gsub(tostring(value), "[^%w]", "")))
end

-- root_package is named after the PROJECT, not the entity: it is where this application's code
-- lives, so it must not move when someone answers a different `entity_name`.
context:set("root_package", context:get("group_id") .. "." .. pkg_segment(context:get("project-name")))
context:set("root_directory", (string.gsub(context:get("root_package"), "%.", "/")))

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

-- SCM — its own page: publishing is a decision about delivery, not about the service. The
-- repository details it reveals are intra-page, so choosing a provider keeps the client here.
local scm = require("scm")
context:page({ title = "Source Control", key = "source_control",
               help = "Optionally create and publish the repository." }, function(ctx)
    scm.prompt(ctx)
end)

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
