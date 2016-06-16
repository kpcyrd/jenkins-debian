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
      | gui        | LXDE      | LXDE  |
#      | gui        | KDE       | KDE   |
      | gui        | minimal   | VT    |
      | gui        | XFCE      | XFCE  |
#      | text       | non-GUI   | VT    |
#      | gui        | Gnome Desktop | Gnome |

  @broken
  Scenario: Attempt to Install KDE, expecting it to fail because #818970
    Given I have started Debian Installer in text mode and stopped at the Tasksel prompt
    And I intend to use text mode
    And I select the KDE task
    And I wait while the bulk of the packages are installed
    And I install GRUB
    And I allow reboot after the install is complete
    And I wait for the reboot
    And I power off the computer
    And the computer is set to boot from ide drive "#{JOB_NAME}"
    When I start the computer
    Then I should see a KDE Login prompt

#  Scenario: Get a useful error from a bogus HTTP proxy
#    Given I get d-i to the HTTP proxy prompt
#    When I set the proxy to "127.23.23.23"
#    Then I should get an error message that mentions the proxy
