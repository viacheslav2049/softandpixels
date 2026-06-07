bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 4567)}"
threads 1, 5
workers 0
