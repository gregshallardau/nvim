-- ~/.config/nvim/lsp/intelephense.lua
return {
  cmd = { "intelephense", "--stdio" },
  filetypes = { "php" },
  root_markers = { "composer.json", ".git" },
  settings = {
    intelephense = {
      telemetry = {
        enabled = false,
      },
      environment = {
        includePaths = {
          vim.fn.expand("~/platform/vendor"),
        },
      },
      files = {
        maxSize = 5000000,
      },
      stubs = {
        "apache", "bcmath", "bz2", "calendar", "com_dotnet", "Core", "ctype",
        "curl", "date", "dba", "dom", "enchant", "exif", "FFI", "fileinfo",
        "filter", "fpm", "ftp", "gd", "gettext", "gmp", "hash", "iconv",
        "imap", "intl", "json", "ldap", "libxml", "mbstring", "meta",
        "mysqli", "oci8", "odbc", "openssl", "pcntl", "pcre", "PDO",
        "pdo_ibm", "pdo_mysql", "pdo_pgsql", "pdo_sqlite", "pgsql",
        "Phar", "posix", "pspell", "readline", "Reflection", "session",
        "shmop", "SimpleXML", "snmp", "soap", "sockets", "sodium",
        "SPL", "sqlite3", "standard", "superglobals", "sysvmsg",
        "sysvsem", "sysvshm", "tidy", "tokenizer", "xml", "xmlreader",
        "xmlrpc", "xmlwriter", "xsl", "Zend OPcache", "zip", "zlib",
        "wordpress", "phpunit",
        "laravel",
      },
      completion = {
        fullyQualifyGlobalConstantsAndFunctions = false,
        insertUseDeclaration = true,
        triggerParameterHints = true,
      },
      diagnostics = {
        undefinedProperties = false,
        undefinedMethods = false,
      },
      format = {
        enable = false,
      },
    },
  },
}
