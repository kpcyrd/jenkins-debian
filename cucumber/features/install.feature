@product
Feature: Doing variations on d-i installs
  As a normal user
  I should be able to install Debian

  Scenario Outline: Install Debian, and boot to a login prompt
    Given I install a <target_ui> Debian system, in <install_ui> mode
    When I start the computer
    Then I should see a Login prompt

    Examples:
      | install_ui | target_ui     |
      | gui        | Minimal       |
      | gui        | non-GUI       |
#      | gui       | Gnome Desktop |
      | text       | Minimal       |
      | text       | non-GUI       |
#      | text       | Gnome Desktop |

#  Scenario: Get a useful error from a bogus HTTP proxy
#    Given I get d-i to the HTTP proxy prompt
#    When I set the proxy to "172.23.23.23"
#    Then I should get an error message that mentions the proxy
