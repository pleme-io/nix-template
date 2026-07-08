# profiles/nixos-security-hardened — a stackable HARDENING layer (axis = "mixin").
#
# A defense-in-depth security layer for a NixOS node. Stack it on top of a
# base profile; nodes override individual knobs as needed. Example wiring in
# a node's default.nix:
#
#   imports = [
#     ../../profiles/server-base.nix          # foundation
#     ../../profiles/nixos-security-hardened   # this layer (a directory)
#     ./configuration.nix                      # node-specific
#   ];
#
# HOUSE STYLE NOTE
# ----------------
# In the real pleme-io fleet this whole file collapses to two lines —
#
#   imports = [ inputs.blackmatter-security.nixosModules.default ];
#   blackmatter.security.hardening.enable = lib.mkDefault true;
#
# — because the vocabulary module (blackmatter-security) owns every hardening
# behavior as a typed option surface (ssh / fail2ban / apparmor / auditd /
# kernel / pam / firewall / tty / tmpfs / tools). A fleet profile is THIN: it
# flips one enable and overrides the exceptions.
#
# This TEMPLATE deliberately inlines the generic nixpkgs equivalents LIVE, so
# the file is standalone-evaluable and teaches WHAT each layer does. Where a
# behavior would come from a blackmatter component, the equivalent blackmatter
# line is named in a comment. Prefer the vocabulary module in a real fleet;
# inline hardening does not compose across the fleet the way a typed option
# surface does.
{ config, lib, pkgs, ... }:
let
  cfg = config.example.securityHardened;
in
{
  ####################################################################
  # A tiny typed option surface so nodes can turn individual layers  #
  # off without mkForce. This mirrors the blackmatter-security shape #
  # (pleme.nixos.security.{ssh,fail2ban,apparmor,...}) in miniature. #
  ####################################################################
  options.example.securityHardened = {
    ssh = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable OpenSSH hardening (key-only, no root password).";
    };
    fail2ban = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable fail2ban brute-force protection.";
    };
    apparmor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the AppArmor mandatory-access-control LSM.";
    };
    auditd = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the kernel audit daemon.";
    };
    kernel = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable kernel + sysctl hardening.";
    };
    firewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the host firewall.";
    };
    tools = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install a small set of security-analysis CLI tools.";
    };
  };

  config = lib.mkMerge [

    ################################################################
    # OpenSSH hardening — key-only auth, no root password login.   #
    # Fleet vocabulary: blackmatter.security.hardening.ssh.enable  #
    ################################################################
    (lib.mkIf cfg.ssh {
      services.openssh = {
        enable = lib.mkDefault true;
        settings = {
          # Passwords are a credential-stuffing surface; require keys.
          PasswordAuthentication = lib.mkDefault false;
          KbdInteractiveAuthentication = lib.mkDefault false;
          # Root may log in for automation, but only with a key.
          PermitRootLogin = lib.mkDefault "prohibit-password";
          # Drop features that widen the attack surface.
          X11Forwarding = lib.mkDefault false;
          AllowAgentForwarding = lib.mkDefault false;
          # Cap unauthenticated work per connection (slows brute force).
          MaxAuthTries = lib.mkDefault 3;
          MaxSessions = lib.mkDefault 10;
        };
        # Drop idle sessions so a walked-away shell can't linger open.
        extraConfig = ''
          ClientAliveInterval 300
          ClientAliveCountMax 2
        '';
      };
    })

    ################################################################
    # fail2ban — ban IPs that fail auth repeatedly.                #
    # Fleet vocabulary: blackmatter.security.hardening.fail2ban.*  #
    ################################################################
    (lib.mkIf cfg.fail2ban {
      services.fail2ban = {
        enable = lib.mkDefault true;
        maxretry = lib.mkDefault 5;
        # A short, escalating ban keeps a fat-fingered legitimate login usable
        # while making automated brute force uneconomic.
        bantime = lib.mkDefault "1h";
        bantime-increment = {
          enable = lib.mkDefault true;
          maxtime = lib.mkDefault "168h"; # one-week ceiling
          factor = lib.mkDefault "2";
        };
        # The sshd jail ships enabled; declare it explicitly so the intent is
        # visible and a node can extend it.
        jails.sshd.settings.enabled = lib.mkDefault true;
      };
    })

    ################################################################
    # AppArmor — mandatory access control LSM.                     #
    # Fleet vocabulary: blackmatter.security.hardening.apparmor.*  #
    ################################################################
    (lib.mkIf cfg.apparmor {
      security.apparmor = {
        enable = lib.mkDefault true;
        # Kill unconfined processes that a profile says should be confined.
        killUnconfinedConfinables = lib.mkDefault true;
      };
    })

    ################################################################
    # auditd — kernel audit trail.                                 #
    # Fleet vocabulary: blackmatter.security.hardening.auditd.*    #
    ################################################################
    (lib.mkIf cfg.auditd {
      security.auditd.enable = lib.mkDefault true;
      security.audit = {
        enable = lib.mkDefault true;
        # A minimal starter ruleset: watch the two files an attacker edits
        # first to add a backdoor account. A real fleet ships a full ruleset
        # (execve, mount, privilege escalation, ...) via the vocabulary.
        rules = [
          "-w /etc/passwd -p wa -k identity"
          "-w /etc/shadow -p wa -k identity"
        ];
      };
    })

    ################################################################
    # Kernel + sysctl hardening.                                   #
    # Fleet vocabulary: blackmatter.security.hardening.kernel.*    #
    # (nixpkgs also ships <nixpkgs/nixos/modules/profiles/         #
    #  hardened.nix>; import it at the node's module-list level    #
    #  for the batch of upstream-vetted defaults.)                 #
    ################################################################
    (lib.mkIf cfg.kernel {
      boot.kernel.sysctl = {
        # Network-facing hardening.
        "net.ipv4.conf.all.rp_filter" = lib.mkDefault 1;      # anti-spoof
        "net.ipv4.conf.default.rp_filter" = lib.mkDefault 1;
        "net.ipv4.conf.all.accept_redirects" = lib.mkDefault 0;
        "net.ipv4.conf.all.send_redirects" = lib.mkDefault 0;
        "net.ipv4.conf.all.accept_source_route" = lib.mkDefault 0;
        "net.ipv6.conf.all.accept_redirects" = lib.mkDefault 0;
        "net.ipv4.icmp_echo_ignore_broadcasts" = lib.mkDefault 1;
        "net.ipv4.tcp_syncookies" = lib.mkDefault 1;          # SYN-flood defense
        # Kernel info-leak / exploit-surface hardening.
        "kernel.kptr_restrict" = lib.mkDefault 2;             # hide kernel pointers
        "kernel.dmesg_restrict" = lib.mkDefault 1;            # non-root can't read dmesg
        "kernel.yama.ptrace_scope" = lib.mkDefault 1;         # restrict ptrace
        "kernel.unprivileged_bpf_disabled" = lib.mkDefault 1;
        "net.core.bpf_jit_harden" = lib.mkDefault 2;
      };

      # Blacklist rarely-used, historically-buggy filesystem + network modules.
      boot.blacklistedKernelModules = lib.mkDefault [
        "dccp" "sctp" "rds" "tipc"   # obscure network protocols
        "cramfs" "freevxfs" "jffs2"  # obscure filesystems
      ];
    })

    ################################################################
    # Host firewall.                                               #
    # Fleet vocabulary: blackmatter.security.hardening.firewall.*  #
    ################################################################
    (lib.mkIf cfg.firewall {
      networking.firewall = {
        enable = lib.mkDefault true;
        # Deny-by-default; flip logging on when triaging a blocked flow.
        logRefusedConnections = lib.mkDefault false;
        # A node opens the ports it actually needs, e.g. in configuration.nix:
        #   networking.firewall.allowedTCPPorts = [ 22 ];
        #
        # On a K3s cluster node, trust the CNI overlay networks. 10.42.0.0/16
        # (pods) and 10.43.0.0/16 (services) are the stock K3s defaults, and
        # cni0 / flannel.1 are the flannel interfaces. Uncomment there:
        #   trustedInterfaces = [ "cni0" "flannel.1" ];
        #   extraCommands = ''
        #     iptables -A nixos-fw -s 10.42.0.0/16 -j nixos-fw-accept
        #     iptables -A nixos-fw -s 10.43.0.0/16 -j nixos-fw-accept
        #   '';
      };
    })

    ################################################################
    # Security-analysis tools.                                     #
    # Fleet vocabulary: blackmatter.security.hardening.tools.*     #
    ################################################################
    (lib.mkIf cfg.tools {
      environment.systemPackages = with pkgs; [
        lynis   # host security auditor
        aide    # file-integrity monitor
      ];
    })
  ];
}
