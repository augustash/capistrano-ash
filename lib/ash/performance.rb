Capistrano::Configuration.instance(:must_exist).load do |config|
  start_times = {}
  end_times   = {}
  order       = []

  on :before do
    order << [:start, current_task]
    start_times[current_task] = Time.now
  end

  on :after do
    order << [:end, current_task]
    end_times[current_task] = Time.now
  end

  config.on :exit do
    print_report(start_times, end_times, order)
  end

  def print_report(start_times, end_times, order)
    def l(s)
      logger.info s
    end

    l " Performance Report"
    l "=========================================================="

    indent = 0
    (order + [nil]).each_cons(2) do |payload1, payload2|
      action, task = payload1
      if action == :start
        l "#{".." * indent}#{task.fully_qualified_name}" unless task == payload2.last
        indent += 1
      else
        indent -= 1
        l "#{".." * indent}#{task.fully_qualified_name} #{(end_times[task] - start_times[task]).to_i}s"
      end
    end
    l "=========================================================="
  end
end
