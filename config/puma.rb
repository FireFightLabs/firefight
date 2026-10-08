threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

port ENV.fetch("PORT", 3000)

# On TERM Puma stops taking requests and lets those in flight finish, for at most as long as a job worker gets
# (config/application.rb), inside the same grace period.
force_shutdown_after 25

plugin :tmp_restart

activate_control_app

plugin :yabeda
plugin :yabeda_prometheus

plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

pidfile ENV["PIDFILE"] if ENV["PIDFILE"]
