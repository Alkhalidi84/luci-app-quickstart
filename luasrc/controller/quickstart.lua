local http = require "luci.http"
local sys  = require "luci.sys"
local fs   = require "nixio.fs"

return function()

    entry({"admin", "nas"}, firstchild(), _("NAS"), 45).dependent = false

    if sys.call("pgrep quickstart >/dev/null") == 0 then

        entry({"admin", "quickstart"}, template("quickstart/home"), _("Dashboard"), 1).leaf = true

        if fs.access("/usr/lib/lua/luci/view/quickstart/main_dev.htm") then
            entry({"admin", "quickstart_dev"}, call("quickstart_dev")).leaf = true
        end

        entry({"admin", "nas", "smart"}, call("quickstart_index"), _("S.M.A.R.T"), 11).leaf = true

        entry({"admin", "network", "network_guide"}, call("networkguide_index"), _("Network Guide"), 10)

        entry({"admin", "network", "network_guide", "pages"}, call("quickstart_index")).leaf = true

        entry({"admin", "network", "interfaceconfig"}, call("quickstart_index"), _("Network Port"), 11).leaf = true

        entry({"admin", "nas", "quickstart"}).dependent = false
        entry({"admin", "nas", "quickstart", "auto_setup"}, post("auto_setup"))
        entry({"admin", "nas", "quickstart", "setup_result"}, call("setup_result"))

    else
        entry({"admin", "quickstart"}, call("redirect_fallback")).leaf = true
    end

end

function networkguide_index()
    http.redirect(luci.dispatcher.build_url("admin", "network", "network_guide", "pages", "network"))
end

function redirect_fallback()
    http.redirect(luci.dispatcher.build_url("admin", "status"))
end

function quickstart_index(param)
    luci.template.render("quickstart/main", {prefix=luci.dispatcher.build_url("admin")})
end

function quickstart_dev(param)
    luci.template.render("quickstart/main_dev", {prefix=luci.dispatcher.build_url("admin")})
end

function auto_setup()
    local os   = require "os"
    local fs   = require "nixio.fs"
    local rshift  = nixio.bit.rshift

    local packages = http.formvalue("packages")
    local pkgs = ""

    if type(packages) == "table" then
        for _, v in pairs(packages) do
            pkgs = pkgs .. " " .. luci.util.shellquote(v)
        end
    else
        if packages and packages ~= "" then
            pkgs = luci.util.shellquote(packages)
        end
    end

    local ret
    if pkgs == "" then
        ret = {
            success = 1,
            scope = "params",
            error = "Parameter 'packages' undefined!",
        }
    else
        local cmd = "/usr/libexec/quickstart/auto_setup.sh " .. pkgs
        cmd = "/etc/init.d/tasks task_add auto_setup " .. luci.util.shellquote(cmd)
        local r = os.execute(cmd .. " >/var/log/auto_setup.stdout 2>/var/log/auto_setup.stderr")

        local e = fs.readfile("/var/log/auto_setup.stderr") or ""
        local o = fs.readfile("/var/log/auto_setup.stdout") or ""

        fs.unlink("/var/log/auto_setup.stderr")
        fs.unlink("/var/log/auto_setup.stdout")

        r = rshift(r,8)

        ret = {
            success = r,
            scope = "taskd",
            error = e,
            detail = o,
        }
    end

    http.prepare_content("application/json")
    http.write_json(ret)
end

function setup_result()
    local fs   = require "nixio.fs"
    local taskd = require "luci.model.tasks"

    local status = taskd.status("auto_setup")
    local ret = {}

    if status.running or status.exit_code ~= 404 then
        ret.success = 0
        ret.result = {
            ongoing = status.running
        }
    else
        ret.success = 404
        ret.error = "task not found"
    end

    http.prepare_content("application/json")
    http.write_json(ret)
end
