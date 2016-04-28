@product
Feature: Doing a trivial d-i install
  As a normal user
  I should be able to do a text-mode install

  Scenario Outline: Install Debian and boot to login prompt
    Given I have installed <type> Debian
    And I start the computer
    Then I wait for a Login Prompt

    Examples:
      | type          |
      | Minimal       |
      | Gnome Desktop |
