{ config, pkgs, ... }:

{

  users.users.ruben = {
    isNormalUser = true;
    description = "Ruben";
    extraGroups =
      [ "docker" "nm-openvpn" "networkmanager" "wheel" "dialout" "adb" ];
  };

  home-manager.users.ruben = { pkgs, config, ... }: {
    home.stateVersion = "23.05";
    home.packages = with pkgs; [
      cntr
      vscode
      speedcrunch
      htop
      direnv
      brave
      minicom
      nixos-24-05.git-cola
      adobe-reader
    ];

    programs.vim = {
      enable = true;
      extraConfig = import ../config-files/vim/.vimrc;
    };

    programs.git = {
      enable = true;
      userName = "Ruben de Schipper";
      userEmail = "rubendeschipper@gmail.com";
      aliases = { lg = "log --oneline"; };
      extraConfig = {
        core = { editor = "vim"; };
        color = { ui = true; };
        push = { default = "simple"; };
        pull = { ff = "only"; };
        init = { defaultBranch = "main"; };
      };
    };

    programs.bash = {
      enable = true;
      bashrcExtra = ''
        source ~/.nix-profile/share/git/contrib/completion/git-prompt.sh
        if type __git_ps1 &> /dev/null; then
          export GIT_PS1_SHOWDIRTYSTATE=1
          export GIT_PS1_SHOWUNTRACKEDFILES=1
          export GIT_PS1_SHOWCOLORHINTS=1
          export GIT_PS1_SHOWUPSTREAM=1
          export PROMPT_DIRTRIM=2
          export PROMPT_COMMAND=' __git_ps1 "\[\033[1;32m\][shlvl-''${SHLVL}\[\e]0;@\w: \w\a\]@\w]\[\033[0m\]" "\\\$\\[\\033[0m\\] "'
        fi

        eval "$(direnv hook bash)"
      '';
      shellAliases = {
        mb = "cd ~/github.com/current-booster/libmodbus-cpp";
        cb = "cd ~/github.com/cb-lund";
      };
    };
  };
}

