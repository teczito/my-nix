{ config, pkgs, ... }:

{

  users.users.ruben = {
    isNormalUser = true;
    description = "Ruben";
    extraGroups = [ "docker" "nm-openvpn" "networkmanager" "wheel" "dialout" "adb" ];
  };

  home-manager.users.ruben = { pkgs, config, ... }: {
    home.stateVersion = "23.05";  
    home.packages =  with pkgs; [
        eclipses.eclipse-cpp
        htop
    ];

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
}

