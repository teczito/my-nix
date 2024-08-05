{ config, pkgs, ... }:

{

  users.users.teczito = {
    isNormalUser = true;
    description = "Teczito";
    extraGroups = [ "docker" "networkmanager" "wheel" "dialout" "adb" ];
  };

  home-manager.users.teczito = { pkgs, ... }: {
    home.stateVersion = "23.05";
    home.packages = with pkgs; [ htop speedcrunch eclipses.eclipse-cpp ];

    programs.git = {
      enable = true;
      userName = "Ruben de Schipper";
      userEmail = "teczito@gmail.com";
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
          export PROMPT_COMMAND=' __git_ps1 "\[\033[1;32m\][\[\e]0;\u@\h: \w\a\]\u@\h:\w]\[\033[0m\]" "\\\$\\[\\033[0m\\] "'
        fi

        alias portenta='cd /home/teczito/northvolt/portenta/httpd-server/'
      '';
    };
  };
}

