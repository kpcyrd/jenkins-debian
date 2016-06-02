def checkpoints
  cp = Hash.new
  cp['disk-for-d-i'] = {
    :description => "Create a disk for Debian Installer tests",
    :parent_checkpoint => nil,
    :steps => [
      'I create a 10 GiB disk named "'+JOB_NAME+'"',
      'I plug ide drive "'+JOB_NAME+'"',
    ]
  }

  ['text', 'gui'].each do |m|
    cp["boot-d-i-#{m}-to-tasksel"] = {
        :description => "I have started Debian Installer in #{m} mode and stopped at the Tasksel prompt",
        :parent_checkpoint => 'disk-for-d-i',
        :steps => [
          "I intend to use #{m} mode",
          'I start the computer',
          'I select the install mode',
          'I select British English',
          'I accept the hostname, using "example.com" as the domain',
          'I set the root password to "rootme"',
          'I set the password for "Philip Hands" to be "verysecret"',
          'I select full-disk, single-filesystem partitioning',
          'I note that the Base system is being installed',
          'I accept the default mirror',
          'I ignore Popcon',
          'we reach the Tasksel prompt',
        ]
    }

    ['minimal', 'non-GUI', 'Gnome', 'XFCE', 'LXDE', 'KDE'].each do |de|
      cp["debian-#{m}-#{de}-install"] = {
          #:temporary => 'XFCE' != de,
          :description => "I install a #{de} Debian system, in #{m} mode",
          :parent_checkpoint => "boot-d-i-#{m}-to-tasksel",
          :steps => [
            "I intend to use #{m} mode",
            "I select the #{de} task",
            'I wait while the bulk of the packages are installed',
            'I install GRUB',
            'I allow reboot after the install is complete',
            'I wait for the reboot',
            'I power off the computer',
            'the computer is set to boot from ide drive "'+JOB_NAME+'"',
          ]
        }
    end
  end

  return cp
end

def live_screenshot()
  debug_log("debug: publishing live screenshot.")
  screen_capture = @screen.capture
  p = screen_capture.getFilename
  if File.exist?(p)
    s = ENV['WORKSPACE']
    s_path = "#{s}/screenshot.png"
    FileUtils.mv(p, s_path)
    convert = IO.popen(['convert',
                      s_path, '-adaptive-resize', '128x96', "#{s}/screenshot-thumb.png",
                      :err => ['/dev/null', 'w'],
                     ])
  end
end

def reach_checkpoint(name)
  scenario_indent = " "*4
  step_indent = " "*6

  step "a computer"
  live_screenshot
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
        live_screenshot
        raise e
      end
      live_screenshot
      debug_log(step_indent + "#{step_action} #{s}", :color => :green)
      step_action = "And"
    end
    $vm.save_snapshot(name)
  end
  live_screenshot
end

# For each checkpoint we generate a step to reach it.
checkpoints.each do |name, desc|
  step_regex = Regexp.new("^#{Regexp.escape(desc[:description])}$")
  Given step_regex do
    reach_checkpoint(name)
  end
end
