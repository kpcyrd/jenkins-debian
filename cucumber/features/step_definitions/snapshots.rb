def checkpoints
  {
    'boot-d-i' => {
      :description => "I have started Debian Installer and stopped at the Tasksel prompt",
      :parent_checkpoint => nil,
      :steps => [
	'I create a 8 GiB disk named "target"',
	'I plug ide drive "target"',
	'I start the computer',
	'I boot to the d-i splash screen',
      ],
    },

    'boot-d-i-to-tasksel' => {
      :description => "I have started Debian Installer and stopped at the Tasksel prompt",
      :parent_checkpoint => 'boot-d-i',
      :steps => [
	'I select text mode and wait for the remote shell',
	'in text mode I select British English',
	'in text mode I accept the hostname, using "example.com" as the domain',
	'in text mode I set the root password to "rootme"',
	'in text mode I set the password for "Philip Hands" to be "verysecret"',
	'in text mode I select full-disk, single-filesystem partitioning',
	'in text mode I note that the Base system is being installed',
	'in text mode I accept the default mirror',
	'in text mode I ignore Popcon',
	'in text mode we reach the Tasksel prompt',
      ],
    },

    'boot-g-i-to-tasksel' => {
      :description => "I have started GUI Debian Installer and stopped at the Tasksel prompt",
      :parent_checkpoint => 'boot-d-i',
      :steps => [
	'I select gui mode and wait for the remote shell',
	'in gui mode I select British English',
	'in gui mode I accept the hostname, using "example.com" as the domain',
	'in gui mode I set the root password to "rootme"',
	'in gui mode I set the password for "Philip Hands" to be "verysecret"',
	'in gui mode I select full-disk, single-filesystem partitioning',
	'in gui mode I note that the Base system is being installed',
	'in gui mode I accept the default mirror',
	'in gui mode I ignore Popcon',
	'in gui mode we reach the Tasksel prompt',
      ],
    },

    'debian-console-install' => {
      :description => "I install a non-GUI Debian system, in text mode",
      :parent_checkpoint => 'boot-d-i-to-tasksel',
      :steps => [
	'in text mode I unset the Desktop task',
	'in text mode I wait while the bulk of the packages are installed',
	'in text mode I install GRUB',
	'in text mode I allow reboot after the install is complete',
	'I wait for the reboot',
	'I power off the computer',
	'the computer is set to boot from ide drive "target"',
      ],
    },

    'debian-gui-console-install' => {
      :description => "I install a non-GUI Debian system, in gui mode",
      :parent_checkpoint => 'boot-g-i-to-tasksel',
      :steps => [
	'in gui mode I unset the Desktop task',
	'in gui mode I wait while the bulk of the packages are installed',
	'in gui mode I install GRUB',
	'in gui mode I allow reboot after the install is complete',
	'I wait for the reboot',
	'I power off the computer',
	'the computer is set to boot from ide drive "target"',
      ],
    },

    'debian-minimal-install' => {
      :description => "I install a Minimal Debian system, in text mode",
      :parent_checkpoint => 'boot-d-i-to-tasksel',
      :steps => [
	'in text mode I unset the Desktop and Print tasks',
	'in text mode I wait while the bulk of the packages are installed',
	'in text mode I install GRUB',
	'in text mode I allow reboot after the install is complete',
	'I wait for the reboot',
	'I power off the computer',
	'the computer is set to boot from ide drive "target"',
      ],
    },

    'debian-gui-minimal-install' => {
      :description => "I install a Minimal Debian system, in gui mode",
      :parent_checkpoint => 'boot-g-i-to-tasksel',
      :steps => [
	'in gui mode I unset the Desktop and Print tasks',
	'in gui mode I wait while the bulk of the packages are installed',
	'in gui mode I install GRUB',
	'in gui mode I allow reboot after the install is complete',
	'I wait for the reboot',
	'I power off the computer',
	'the computer is set to boot from ide drive "target"',
      ],
    },

    'debian-gnome-install' => {
      :description => "I install a Gnome Desktop Debian system, in text mode",
      :parent_checkpoint => 'boot-d-i-to-tasksel',
      :steps => [
	'in text mode I select the Desktop task',
	'in text mode I wait while the vast bulk of the packages are installed',
	'in text mode I install GRUB',
	'in text mode I allow reboot after the install is complete',
	'I wait for the reboot',
	'I power off the computer',
	'the computer is set to boot from ide drive "target"',
      ],
    },

    'debian-gui-gnome-install' => {
      :description => "I install a Gnome Desktop Debian system, in gui mode",
      :parent_checkpoint => 'boot-g-i-to-tasksel',
      :steps => [
	'in gui mode I select the Desktop task',
	'in gui mode I wait while the vast bulk of the packages are installed',
	'in gui mode I install GRUB',
	'in gui mode I allow reboot after the install is complete',
	'I wait for the reboot',
	'I power off the computer',
	'the computer is set to boot from ide drive "target"',
      ],
    },
  }
end

def reach_checkpoint(name)
  scenario_indent = " "*4
  step_indent = " "*6

  step "a computer"
  if VM.snapshot_exists?(name)
    $vm.restore_snapshot(name)
    post_snapshot_restore_hook
  else
    checkpoint = checkpoints[name]
    checkpoint_description = checkpoint[:description]
    parent_checkpoint = checkpoint[:parent_checkpoint]
    steps = checkpoint[:steps]
    if parent_checkpoint
      if VM.snapshot_exists?(parent_checkpoint)
        $vm.restore_snapshot(parent_checkpoint)
      else
        reach_checkpoint(parent_checkpoint)
      end
      post_snapshot_restore_hook
    end
    debug_log(scenario_indent + "Checkpoint: #{checkpoint_description}",
              :color => :white)
    step_action = "Given"
    if parent_checkpoint
      parent_description = checkpoints[parent_checkpoint][:description]
      debug_log(step_indent + "#{step_action} #{parent_description}",
                :color => :green)
      step_action = "And"
    end
    steps.each do |s|
      begin
        step(s)
      rescue Exception => e
        debug_log(scenario_indent +
                  "Step failed while creating checkpoint: #{s}",
                  :color => :red)
        raise e
      end
      debug_log(step_indent + "#{step_action} #{s}", :color => :green)
      step_action = "And"
    end
    $vm.save_snapshot(name)
  end
end

# For each checkpoint we generate a step to reach it.
checkpoints.each do |name, desc|
  step_regex = Regexp.new("^#{Regexp.escape(desc[:description])}$")
  Given step_regex do
    reach_checkpoint(name)
  end
end
