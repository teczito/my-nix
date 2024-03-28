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
        vscode
        speedcrunch
        htop
        direnv
        brave
        minicom
        git-cola
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

    programs.bash = {
      enable = true;
      bashrcExtra = ''
        eval "$(direnv hook bash)"
        source ~/.nix-profile/share/git/contrib/completion/git-prompt.sh
        if type __git_ps1 &> /dev/null; then
          export GIT_PS1_SHOWDIRTYSTATE=1
          export GIT_PS1_SHOWUNTRACKEDFILES=1
          export GIT_PS1_SHOWCOLORHINTS=1
          export GIT_PS1_SHOWUPSTREAM=1
          export PROMPT_DIRTRIM=2
          export PROMPT_COMMAND=' __git_ps1 "\[\033[1;32m\][''${IN_NIX_SHELL/impure/shell }\[\e]0;\u@\h: \w\a\]\u@\h:\w]\[\033[0m\]" "\\\$\\[\\033[0m\\] "'
        fi
        '';
      shellAliases = {
        mb = "cd ~/github.com/current-booster/libmodbus-cpp";
        cb = "cd ~/github.com/current-booster";
        };
      };
  };
}

