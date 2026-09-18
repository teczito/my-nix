{ config, pkgs, ... }:

{
  users.users.ruben = {
    isNormalUser = true;
    description = "Ruben";
    extraGroups = [
      "docker"
      "networkmanager"
      "wheel"
    ];
  };

  home-manager.users.ruben =
    { pkgs, config, ... }:
    {
      # The CLI base, wanted on every machine. GUI apps and bench tools are in
      # ./desktop.nix.
      home.packages = with pkgs; [
        bat
        cntr
        direnv
        htop
        nix-index
        nix-tree
        tree
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

          # Some custom bindings
          bind C-a select-window -t:!
          bind a send-prefix

          # easy-to-remember split pane commands
          bind | split-window -h -c "#{pane_current_path}"
          bind - split-window -v -c "#{pane_current_path}"
          bind C-c new-window -c "#{pane_current_path}"
        '';
      };

      programs.vim = {
        enable = true;
        extraConfig = import ../../config-files/vim/.vimrc;
      };

      programs.lazygit = {
        enable = true;
      };

      # `enable` belongs to programs.git, not inside settings. It sat one level
      # too deep here for a long time, which left programs.git.enable false and
      # meant no git config was ever generated.
      programs.git = {
        enable = true;
        settings = {
          # `settings` is the gitconfig itself (it is the renamed `extraConfig`),
          # so these are real git sections. The flat `userName` / `userEmail` /
          # `aliases` that used to be here were home-manager option names, not
          # git ones, and have their own renames: user.name, user.email, alias.
          user = {
            name = "Ruben de Schipper";
            email = "rubendeschipper@gmail.com";
          };
          alias = {
            lg = "log --oneline";
          };
          core = {
            editor = "vim";
            whitespace = "cr-at-eol";
          };

          # Moved out of a hand-written ~/.gitconfig. Both entries are inert as
          # things stand -- /etc/nixos is owned by ruben:users, so git needs no
          # exception for it, and /home/ci/zt600-firmware does not exist -- but
          # they cost nothing and cover the case where a repo is checked out
          # under another owner.
          safe = {
            directory = [
              "/etc/nixos"
              "/home/ci/zt600-firmware"
            ];
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
          source /run/current-system/sw/share/bash-completion/completions/git-prompt.sh
          if type __git_ps1 &> /dev/null; then
            export GIT_PS1_SHOWDIRTYSTATE=1
            export GIT_PS1_SHOWUNTRACKEDFILES=1
            export GIT_PS1_SHOWCOLORHINTS=1
            export GIT_PS1_SHOWUPSTREAM=1
            export PROMPT_DIRTRIM=2
            export PROMPT_COMMAND=' __git_ps1 "\[\033[1;32m\][shlvl-''${SHLVL} \h\[\e]0;\h@\w: \w\a\]@\w]\[\033[0m\]" "\\\$\\[\\033[0m\\] "'
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
          ltr = "l -ltr";
        };
      };
    };
}
