{ pkgs, lib, config, ... }:
let
  app = "caddyphp";
  dataDir = "/var/www/";
in {

  services.phpfpm.pools.${app} = {
    user = app;
    settings = {
      "listen.owner" = config.services.caddy.user;
      "pm" = "dynamic";
      "pm.max_children" = 32;
      "pm.max_requests" = 500;
      "pm.start_servers" = 2;
      "pm.min_spare_servers" = 2;
      "pm.max_spare_servers" = 5;
      "php_admin_value[error_log]" = "stderr";
      "php_admin_flag[log_errors]" = true;
      "catch_workers_output" = true;
    };
    phpEnv."PATH" = lib.makeBinPath [ pkgs.php ];
  };

  services.phpfpm.phpOptions = ''
    extension=${pkgs.phpExtensions.redis}/lib/php/extensions/redis.so
    extension=${pkgs.phpExtensions.apcu}/lib/php/extensions/apcu.so
  '';

  services.caddy = {
    enable = true;
    virtualHosts."http://localhost" = {
      extraConfig = ''
        root * ${dataDir}
        file_server
        php_fastcgi unix//run/phpfpm/${app}.sock
      '';
    };
  };

  users.users.${app} = {
    isSystemUser = true;
    createHome = true;
    home = dataDir;
    group  = app;
  };
  users.groups.${app} = {};
}
