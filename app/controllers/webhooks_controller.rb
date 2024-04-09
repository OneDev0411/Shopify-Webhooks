# frozen_string_literal: true

class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_webhook
  before_action :set_object_id, only: [:product, :delete_product, :collection]
  before_action :set_payload, only: [:order, :shop_update]

  #products/create, products/update
  def product
    return unless ensure_redis_entry_exists

    enqueue_job('ShopWorker::UpdateProductIfUsedInOfferJob', 
                 [@myshopify_domain, @object_id], 'product', Time.now.to_i)
    head :ok and return
  end

  def delete_product
    return unless ensure_redis_entry_exists

    enqueue_job('ShopWorker::MarkProductDeletedJob',
                 [@myshopify_domain, @object_id], 'low', Time.now.to_i)
    head :ok and return
  end

  #collections/create, collections/update
  def collection
    return unless ensure_redis_entry_exists

    enqueue_job('ShopWorker::UpdateCollectionIfUsedInOfferJob', 
                 [@myshopify_domain, @object_id], 'low', Time.now.to_i)
    head :ok and return
  end

  def order
    enqueue_job('ShopWorker::RecordOrderJob', [@myshopify_domain, order_opts],
                'orders', Time.now.to_i + 10)
    enqueue_job('ShopWorker::SaveOfferSaleJob', [order_opts],
                 'sale_stats', Time.now.to_i + 11) unless @payload['cart_token'].nil?
    head :ok and return
  end

  def app_uninstalled
    enqueue_job('ShopWorker::MarkShopAsCancelledJob', [@myshopify_domain], 'low', Time.now.to_i + 10)
    head :ok and return
  end

  def shop_update
    enqueue_job('ShopWorker::UpdateShopJob', [@myshopify_domain, shop_opts], 'low', Time.now.to_i + 10)
    head :ok and return
  end

  #theme/publish
  def themes_publish
    enqueue_job('ShopWorker::ThemeUpdateJob',  [@myshopify_domain], 'themes', Time.now.to_i + 10)
    head :ok and return
  end

  private

  def set_object_id
    @object_id = params[:detail].present? ? params[:detail][:payload][:id] : params[:webhook][:id]
  end

  def set_payload
    @payload = params[:detail].present? ? params[:detail][:payload] : params[:webhook]
  end

  def order_opts
    {
      shopify_id: @payload['id'],
      items: (@payload['line_items'] || []).map{ |l| l['product_id'] }.compact.sort,
      item_variants: (@payload['line_items'] || []).map{ |l| { variant_id: l['variant_id'], 
                                                               quantity: l['quantity'], 
                                                               price: l['price'], 
                                                               discount: l['discount_allocations'] } },
      discount_code: @payload['discount_codes']&.first&.dig('code'),
      shopper_country: @payload.dig('billing_address', 'country_code'),
      referring_site: @payload['referring_site'],
      orders_count: @payload.dig('customer', 'orders_count'),
      total: @payload['total_price'],
      cart_token: @payload['cart_token']
    }
  end

  def shop_opts
    {
      'name' => @payload['name'],
      'shopify_id' => @payload['id'],
      'email' => @payload['email'],
      'timezone' => @payload['timezone'],
      'iana_timezone' => @payload['iana_timezone'],
      'money_format' => @payload['money_format'],
      'shopify_plan_name' => @payload['plan_display_name'],
      'shopify_plan_internal_name' => @payload['plan_name'],
      'custom_domain' => @payload['domain'],
      'opened_at' => @payload['created_at']
    }
  end

  def enqueue_job(job_class, args, queue, time)
    Sidekiq::Client.push('class' => job_class, 'args' => args, 'queue' => queue, 'at' => time)
  end

  def verify_webhook
    request_body = request.body.read.to_s
    data = JSON.parse(request_body)
    if data['detail'].present?
      @myshopify_domain = data['detail']['metadata']['X-Shopify-Shop-Domain']
      @shopify_webhook_topic = data['detail']['metadata']['X-Shopify-Topic']
      @shopify_product_id = data['detail']['metadata']['X-Shopify-Product-Id']
      @shopify_collection_id = data['detail']['metadata']['X-Shopify-Collection-Id']
    else
      hmac_header = request.headers['HTTP_X_SHOPIFY_HMAC_SHA256']
      puts "------ Inside webhook verify: hmac_header #{hmac_header} ------\n"
      digest  = OpenSSL::Digest.new('sha256')
      calculated_hmac = Base64.encode64(OpenSSL::HMAC.digest(digest, ENV['SHOPIFY_APP_SECRET'], request_body)).strip
      puts "------ Inside webhook verify: calculated_hmac #{calculated_hmac} ------\n"
      unless calculated_hmac == hmac_header
        puts "------ Inside webhook verify: calculated webhook don't matched\n" * 5
        Rollbar.info('Denied Webhook', {calculated: calculated_hmac, actual: hmac_header, request: request})
        render text: 'Not Authorized', status: :unauthorized and return
      end
      puts "------ Inside webhook verify: calculated webhook matched\n" * 5
      @myshopify_domain = request.headers['HTTP_X_SHOPIFY_SHOP_DOMAIN']
    end
  end

  def ensure_redis_entry_exists
    type = @shopify_webhook_topic&.split('/')&.first
    return false unless type

    formatted_type = ActiveSupport::Inflector.singularize(type)
    handle_entry_type(formatted_type, instance_variable_get("@shopify_#{formatted_type}_id")) if ensure_type?(formatted_type)
  end
  
  def handle_entry_type(type, id)
    @key = "shopify_#{type}_#{id}"
  
    case @shopify_webhook_topic
    when "#{type}s/create"
      return true
    when "#{type}s/update", "#{type}s/delete"
      return $redis_cache.exists(@key) == 1 ? true : false
    end
  end

  def ensure_type?(type)
    ['product', 'collection'].include?(type)
  end
end
