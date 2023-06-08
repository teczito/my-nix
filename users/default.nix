{ config, pkgs, ... }:

{

  users.users.ruben = {
    isNormalUser = true;
    description = "Ruben";
    extraGroups = [ "docker" "networkmanager" "wheel" "dialout" "adb" ];
  };

  users.users.teczito = {
    isNormalUser = true;
    description = "Teczito";
    extraGroups = [ "docker" "networkmanager" "wheel" "dialout" "adb" ];
  };

  home-manager.users.ruben = { pkgs, ... }: {
      home.stateVersion = "23.05";  
      home.packages =  with pkgs; [ htop ];

      programs.git = {
        enable = true;
        userName = "Ruben de Schipper";
        userEmail = "rubendeschipper@gmail.com";
          aliases = {
            lg = "log --oneline";
          };
          extraConfig = {
            core = {
              editor = "vim";
            };
            color = {
              ui = true;
            };
            push = {
              default = "simple";
            };
            pull = {
              ff = "only";
            };
            init = {
              defaultBranch = "main";
            };
          };
      };
  };

  home-manager.users.teczito = { pkgs, ... }: {
      home.stateVersion = "23.05";  
      home.packages =  with pkgs; [ htop ];

      programs.git = {
        enable = true;
        userName = "Ruben de Schipper";
        userEmail = "teczito@gmail.com";
          aliases = {
            lg = "log --oneline";
          };
          extraConfig = {
            core = {
              editor = "vim";
            };
            color = {
              ui = true;
            };
            push = {
              default = "simple";
            };
            pull = {
              ff = "only";
            };
            init = {
              defaultBranch = "main";
            };
          };
      };
  };
}

