local function install_dbee()
  if vim.fn.has("win32") ~= 1 then
    require("dbee").install()
    return
  end

  local manifest = require("dbee.install.__manifest")
  local machine = vim.uv.os_uname().machine:lower()
  local arch = ({ x86_64 = "amd64", aarch64 = "arm64" })[machine] or machine
  local url = assert(manifest.urls["windows/" .. arch], "No DBee binary is available for Windows/" .. arch)
  local install_dir = vim.fn.stdpath("data") .. "/dbee/bin"
  local build_dir = vim.fn.stdpath("cache") .. "/dbee/build"
  local archive = build_dir .. "/dbee.tar.gz"

  vim.fn.mkdir(install_dir, "p")
  vim.fn.mkdir(build_dir, "p")

  local download = vim.system({ "curl.exe", "-sfLo", archive, url }, { text = true }):wait()
  assert(download.code == 0, download.stderr)

  local extract = vim.system({ "tar.exe", "-xzf", archive, "-C", install_dir }, { text = true }):wait()
  assert(extract.code == 0, extract.stderr)
end

return {
  {
    "kndndrj/nvim-dbee",
    dependencies = {
      "MunifTanjim/nui.nvim",
    },
    build = install_dbee,
    cmd = "Dbee",
    keys = {
      {
        "<leader>db",
        function()
          require("dbee").toggle()
        end,
        desc = "Toggle database client",
      },
    },
    opts = {},
  },
}
