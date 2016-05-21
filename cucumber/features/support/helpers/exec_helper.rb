require 'json'
require 'socket'
require 'io/wait'

class VMCommand

  attr_reader :cmd, :returncode, :stdout, :stderr

  def initialize(vm, cmd, options = {})
    @cmd = cmd
    @returncode, @stdout, @stderr = VMCommand.execute(vm, cmd, options)
  end

  def VMCommand.wait_until_remote_shell_is_up(vm, timeout = 180)
    try_for(timeout, :msg => "Remote shell seems to be down") do
    sleep(20)
      Timeout::timeout(10) do
        VMCommand.execute(vm, "echo 'true'")
      end
    end
  end

  # The parameter `cmd` cannot contain newlines. Separate multiple
  # commands using ";" instead.
  # If `:spawn` is false the server will block until it has finished
  # executing `cmd`. If it's true the server won't block, and the
  # response will always be [0, "", ""] (only used as an
  # ACK). execute() will always block until a response is received,
  # though. Spawning is useful when starting processes in the
  # background (or running scripts that does the same) like our
  # onioncircuits wrapper, or any application we want to interact with.
  def VMCommand.execute(vm, cmd, options = {})
    options[:user] ||= "root"
    options[:spawn] ||= false
    type = options[:spawn] ? "spawn" : "call"
    socket = TCPSocket.new("127.0.0.1", vm.get_remote_shell_port)
    debug_log("#{type}ing as #{options[:user]}: #{cmd}")
    begin
      #socket.puts(JSON.dump([type, options[:user], cmd]))
      socket.puts( "\n")
      sleep(1)
      socket.puts( "\003")
      sleep(1)
      socket.puts( cmd + "\n")
      sleep(1)
      while socket.ready?
        s = socket.readline(sep = "\n").chomp("\n")
        debug_log("#{type} read: #{s}") if not(options[:spawn])
        if ('true' == s) then
          break
        end
      end
    ensure
      socket.close
    end
    if ('true' == s)
      return true
    else
      return VMCommand.execute(vm, cmd, options)
    end
  end

  def success?
    return @returncode == 0
  end

  def failure?
    return not(success?)
  end

  def to_s
    "Return status: #{@returncode}\n" +
    "STDOUT:\n" +
    @stdout +
    "STDERR:\n" +
    @stderr
  end

end
