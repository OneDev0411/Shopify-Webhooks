# frozen_string_literal: true

class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_webhook

  #products/create, products/update
  def product
    if params[:detail].present?
      product_id = params[:detail][:payload][:id]
    else
      product_id = params[:webhook][:id]
    end
    create_job_unless_exists('ShopWorker::UpdateProductIfUsedInOfferJob', [@myshopify_domain, product_id])
    logger.info "------ Returning from the function ------\n"
    
    head :ok and return
  end

  #We don't use this webhook, but maybe we should
  def product_deleted
    product_id = @payload['id']
    create_job_unless_exists('ShopWorker::MarkProductDeletedJob', [@myshopify_domain, product_id])
    head :ok and return
  end

  #collections/create, collections/update
  def collection
    if params[:detail].present?
      collection_id = params[:detail][:payload][:id]
    else
      collection_id = params[:webhook][:id]
    end
    create_job_unless_exists('ShopWorker::UpdateCollectionIfUsedInOfferJob', [@myshopify_domain, collection_id])
    head :ok and return
  end

  def order
    if params[:detail].present?
      payload = params[:detail][:payload]
    else
      payload = params[:webhook]
    end
    discount_code = if payload['discount_codes'] && payload['discount_codes'][0]
      payload['discount_codes'][0]['code']
    else
      nil
    end
    order_opts = {
      shopify_id: payload['id'],
      items: (payload['line_items'] || []).map{|l| l['product_id'] }.compact.sort,
      item_variants: (payload['line_items'] || []).map{|l| { variant_id: l['variant_id'], quantity: l['quantity'], price: l['price'], discount: l['discount_allocations'] } },
      discount_code: discount_code,
      shopper_country: payload['billing_address'].present? ? payload['billing_address']['country_code'] : nil,
      referring_site: payload['referring_site'],
      orders_count: payload['customer'].present? ? payload['customer']['orders_count'] : nil,
      total: payload['total_price'],
      cart_token: payload['cart_token']
    }
    Sidekiq::Client.push('class' => 'ShopWorker::RecordOrderJob', 'args' => [@myshopify_domain, order_opts], 'queue' => 'low', 'at' => Time.now.to_i + 10)
    unless payload['cart_token'].nil?
      Sidekiq::Client.push('class' => 'ShopWorker::SaveOfferSaleJob', 'args' => [order_opts], 'queue' => 'sale_stats', 'at' => Time.now.to_i + 11)
    end
    head :ok and return
  end

  def app_uninstalled
    Sidekiq::Client.push('class' => 'ShopWorker::MarkShopAsCancelledJob', 'args' => [@myshopify_domain], 'queue' => 'low', 'at' => Time.now.to_i + 10)
    head :ok and return
  end

  def shop_update
    if params[:detail].present?
      payload = params[:detail][:payload]
    else
      payload = params[:webhook]
    end
    shopts = {
      'name' => payload['name'],
      'shopify_id' => payload['id'],
      'email' => payload['email'],
      'timezone' => payload['timezone'],
      'iana_timezone' => payload['iana_timezone'],
      'money_format' => payload['money_format'],
      'shopify_plan_name' => payload['plan_display_name'],
      'shopify_plan_internal_name' => payload['plan_name'],
      'custom_domain' => payload['domain'],
      'opened_at' => payload['created_at']
    }
    Sidekiq::Client.push('class' => 'ShopWorker::UpdateShopJob', 'args' => [@myshopify_domain, shopts], 'queue' => 'low', 'at' => Time.now.to_i + 10)
    
    head :ok and return
  end

  private
    def create_job_unless_exists(job_class, args)
      puts "~~~~~~~~~~~~~~~~~~~~~~~"
      if check_duplicates?
        @q.entries.each do |job|
          if job['class'] == job_class && job['args'].is_a?(Array) && job['args'] == args
            return
          end
        end
      end
      puts "~~~~~~~~~~Pushing the job in Sidekiq~~~~~~~~~~~~"
      puts job_class
      puts args
      Sidekiq::Client.push('class' => job_class, 'args' => args, 'queue' => 'low', 'at' => Time.now.to_i)
    end

    def verify_webhook
      data = JSON.parse(request.body.read.to_s)
      if data['detail'].present?
        @myshopify_domain = data['detail']['metadata']['X-Shopify-Shop-Domain']
      else
        hmac_header = request.headers['HTTP_X_SHOPIFY_HMAC_SHA256']
        logger.info "------ Inside webhook verify: hmac_header #{hmac_header} ------\n"

        digest  = OpenSSL::Digest.new('sha256')
        calculated_hmac = Base64.encode64(OpenSSL::HMAC.digest(digest, ENV['SHOPIFY_APP_SECRET'], request.body.read.to_s)).strip
        logger.info "------ Inside webhook verify: calculated_hmac #{calculated_hmac} ------\n"
        unless calculated_hmac == hmac_header
          logger.info "------ Inside webhook verify: calculated webhook don't matched\n" * 5
          Rollbar.info('Denied Webhook', {calculated: calculated_hmac, actual: hmac_header, request: request})
          render text: 'Not Authorized', status: :unauthorized and return
        end
        logger.info "------ Inside webhook verify: calculated webhook matched\n" * 5
        @myshopify_domain = request.headers['HTTP_X_SHOPIFY_SHOP_DOMAIN']
      end
      @q = Sidekiq::Queue.new('low')
    end

    def check_duplicates?
      logger.info "------ Inside check duplicates: #{ENV.fetch('CHECK_DUPLICATE_JOBS') == 'true'} ------\n"
      ENV.fetch('CHECK_DUPLICATE_JOBS') == 'true'
    end
end
