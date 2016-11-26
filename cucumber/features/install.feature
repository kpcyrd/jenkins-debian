@product
Feature: Doing variations on d-i installs
  As a normal user
  I should be able to install Debian

  @both-ui
  Scenario Outline: Install Debian, and boot to a login prompt
    Given I install a <target_ui> Debian system, in <install_ui> mode
    When I start the computer
    Then I should see a <login> Login prompt

    Examples:
      | install_ui | target_ui | login |
      | gui        | minimal   | VT    |
      | text       | non-GUI   | VT    |
      #| gui        | Gnome     | Gnome |
      #| gui        | LXDE      | LXDE  |
      #| gui        | XFCE      | XFCE  |
      #| gui        | KDE       | KDE   |

  @gui
  Scenario Outline: Install Debian, and boot to a login prompt
    Given I install a <target_ui> Debian system, in gui mode
    When I start the computer
    Then I should see a <login> Login prompt

    Examples:
      | target_ui | login |
      | non-GUI   | VT    |
      | XFCE      | XFCE  |
      | KDE       | KDE   |

  @text-ui
  Scenario Outline: Install Debian, and boot to a login prompt
    Given I install a <target_ui> Debian system, in text mode
    When I start the computer
    Then I should see a <login> Login prompt

    Examples:
      | target_ui | login |
      | minimal   | VT    |
      | Gnome     | Gnome |
      | LXDE      | LXDE  |

  @broken
  Scenario: Attempt to Install Gnome, expecting it to fail because X doesn't start for some reason
    Given I have started Debian Installer in text mode and stopped at the Tasksel prompt
    And I intend to use text mode
    And I select the Gnome task
    And I wait while the bulk of the packages are installed
    And I install GRUB
    And I allow reboot after the install is complete
    And I wait for the reboot
    And I power off the computer
    And the computer is set to boot from ide drive
    When I start the computer
    Then I should see a Gnome Login prompt

#  Scenario: Get a useful error from a bogus HTTP proxy
#    Given I get d-i to the HTTP proxy prompt
#    When I set the proxy to "127.23.23.23"
#    Then I should get an error message that mentions the proxy

  # this is useful for just proving that the d-i image is able to boot
  @trivial
  Scenario: Minimal Boot test
    Given a disk is created for Debian Installer tests
    And I intend to use gui mode
    When I start the computer
    Then I select the install mode

  @preseed
  Scenario: Preseed using hands.com with checksum
    Given a disk is created for Debian Installer tests
    And I intend to use gui mode
    And I intend to boot with options: auto=true priority=critical url=hands.com classes=jenkins.debian.org/pb10;loc/gb;hands.com/general-tweaks;setup/users;partition/atomic;desktop/lxde hands-off/checksigs=true DEBCONF_DEBUG=5
    And I start the computer
    And I select the install mode
    And I expect package installation to start
    And I wait while the bulk of the packages are installed
    And the VM shuts down within 20 minutes
    When the computer is set to boot from ide drive
    And I start the computer
    Then I should see a LXDE Login prompt

  @debedu
  Scenario: Install default Debian-Edu
    Given a disk is created for Debian Edu tests
    And I intend to use gui mode
    And I intend to boot with options: url=hands.com/d-i/bug/edu-plymouth/preseed.cfg
    And I start the computer
    And I select the install mode
    And I select British English
    And I select Combi Debian-Edu profile
    And I use the Debian-Edu Automatic Partitioning
    And I ignore Popcon
    And I set the root password to "rootme"
    And I set the password for "Philip Hands" to be "verysecret"
    And I wait while the partitions are made
    And I note that the Base system is being installed
    And I wait patiently for the package installation to start
    And I wait while the bulk of the packages are installed
    And I install GRUB
    And I allow reboot after the install is complete
    And I wait for the reboot
    And I power off the computer
    And the computer is set to boot from ide drive
    When I start the computer
    Then I should see a Gnome Login prompt
