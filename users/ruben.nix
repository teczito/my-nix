{ config, pkgs, ... }:

{

  users.users.ruben = {
    isNormalUser = true;
    description = "Ruben";
    extraGroups = [
      "docker"
      "nm-openvpn"
      "networkmanager"
      "wheel"
      "dialout"
      "adb"
    ];
  };

  home-manager.users.ruben =
    { pkgs, config, ... }:
    {
      home.stateVersion = "23.05";
      home.packages = with pkgs; [
        nixos-24-11.adobe-reader
        bat
        brave
        cntr
        direnv
        git-cola
        htop
        iw
        minicom
        nix-index
        nix-tree
        shutter
        speedcrunch
        tree
        vscode
      ];

      programs.tmux = {
        enable = true;
        shortcut = "a";
        keyMode = "vi";
        clock24 = true;
        escapeTime = 0;
        plugins = with pkgs; [
          tmuxPlugins.better-mouse-mode
        ];

        extraConfig = ''
          # https://old.reddit.com/r/tmux/comments/mesrci/tmux_2_doesnt_seem_to_use_256_colors/
          set -g default-terminal "xterm-256color"
          set -ga terminal-overrides ",*256col*:Tc"
          set -ga terminal-overrides '*:Ss=\E[%p1%d q:Se=\E[ q'
          set-environment -g COLORTERM "truecolor"
          set -g visual-bell on

          # easy-to-remember split pane commands
          bind | split-window -h -c "#{pane_current_path}"
          bind - split-window -v -c "#{pane_current_path}"
          bind C-c new-window -c "#{pane_current_path}"
        '';
      };

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
          source ~/.nix-profile/share/git/contrib/completion/git-prompt.sh
          if type __git_ps1 &> /dev/null; then
            export GIT_PS1_SHOWDIRTYSTATE=1
            export GIT_PS1_SHOWUNTRACKEDFILES=1
            export GIT_PS1_SHOWCOLORHINTS=1
            export GIT_PS1_SHOWUPSTREAM=1
            export PROMPT_DIRTRIM=2
            export PROMPT_COMMAND=' __git_ps1 "\[\033[1;32m\][shlvl-''${SHLVL}\[\e]0;@\w: \w\a\]@\w]\[\033[0m\]" "\\\$\\[\\033[0m\\] "'
          fi

          nixify() {
            if [ ! -e ./.envrc ]; then
              echo "use nix" > .envrc
              direnv allow
            fi
            if [[ ! -e shell.nix ]] && [[ ! -e default.nix ]]; then
              cat > default.nix <<'EOF'
          with import <nixpkgs> {};
          mkShell {
            nativeBuildInputs = [
              bashInteractive
            ];
          }
          EOF
              vim default.nix
            fi
          }

          flakify() {
            if [ ! -e flake.nix ]; then
              nix flake new -t github:nix-community/nix-direnv .
              echo ".direnv/" >> .gitignore
              echo ".envrc" >> .gitignore
            elif [ ! -e .envrc ]; then
              echo "use flake" > .envrc
              direnv allow
            fi
            vim flake.nix
          }

          eval "$(direnv hook bash)"
        '';
        shellAliases = {
          mb = "cd ~/github.com/current-booster/libmodbus-cpp";
          dcdc = "cd ~/github.com/lund-dcdc-kicad";
          zt600-ctrl = "cd ~/github.com/zt600-control";
          zt600-fw = "cd ~/github.com/zt600-firmware";
        };
      };
    };
}
