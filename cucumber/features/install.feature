@product
Feature: Doing variations on d-i installs
  As a normal user
  I should be able to install Debian

  Scenario Outline: Install Debian, and boot to a login prompt
    Given I install a <target_ui> Debian system, in <install_ui> mode
    When I start the computer
    Then I should see a <login> Login prompt

    Examples:
      | install_ui | target_ui | login |
#      | gui        | Gnome     | Gnome |   #  FIXME -- X fails to start at present -- possibly related to "qxl too old" seen on flickering console, which seems like it might be something to do with 'spice'
      | gui        | minimal   | VT    |
      | gui        | LXDE      | LXDE  |
      | gui        | XFCE      | XFCE  |
      | gui        | KDE       | KDE   |
#      | text       | non-GUI   | VT    |

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
    And I intend to boot with options "auto=true priority=critical url=hands.com classes=jenkins.debian.org/pb10;loc/gb;hands.com/general-tweaks;setup/users;partition/atomic;desktop/lxde hands-off/checksigs=true DEBCONF_DEBUG=5"
    When I start the computer
    And I select the install mode
    And the VM shuts down within 20 minutes
    And the computer is set to boot from ide drive
    And I start the computer
    Then I should see a LXDE Login prompt
