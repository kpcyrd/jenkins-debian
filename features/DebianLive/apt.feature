@product
Feature: Installing packages through APT
  As a Tails user
  I should be able to install packages using APT

  Background:
    Given a computer
    And I capture all network traffic
    And I start the computer
    And the computer boots DebianLive
    And I save the state so the background can be restored next scenario

  Scenario: APT sources are configured correctly
    Then the only hosts in APT sources are "ftp.us.debian.org,http.debian.net,ftp.debian.org,security.debian.org"

  Scenario: Install packages using apt-get
    When I update APT using apt-get
    Then I should be able to install a package using apt-get

