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
      Timeout::timeout(20) do
        VMCommand.execute(vm, "echo 'hello?'")
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
      sleep 0.5
      while socket.ready?
        s = socket.recv(1024)
        debug_log("#{type} pre-exit-debris: #{s}") if not(options[:spawn])
      end
      socket.puts( "\nexit\n")
      sleep 1
      s = socket.readline(sep = "\007")
      debug_log("#{type} post-exit-read: #{s}") if not(options[:spawn])
      while socket.ready?
        s = socket.recv(1024)
        debug_log("#{type} post-exit-debris: #{s}") if not(options[:spawn])
      end
      socket.puts( cmd + "\n")
      s = socket.readline(sep = "\000")
      debug_log("#{type} post-cmd-read: #{s}") if not(options[:spawn])
      s.chomp!("\000")
    ensure
      debug_log("closing the remote-command socket") if not(options[:spawn])
      socket.close
    end
    (s, s_err, x) = s.split("\037")
    s_err = "" if s_err.nil?
    (s, s_retcode, y) = s.split("\003")
    (s, s_out, z) = s.split("\002")
    s_out = "" if s_out.nil?

    if (s_retcode.to_i.to_s == s_retcode.to_s && x.nil? && y.nil? && z.nil?) then
      debug_log("returning [returncode=`#{s_retcode.to_i}`,\n\toutput=`#{s_out}`,\n\tstderr=`#{s_err}`]\nwhile discarding `#{s}`.") if not(options[:spawn])
      return [s_retcode.to_i, s_out, s_err]
    else
      debug_log("failed to parse results, retrying\n")
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
