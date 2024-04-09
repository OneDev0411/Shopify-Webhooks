
$redis_cache = Redis.new(url: ENV['REDIS_CACHE_URL'], ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE })
