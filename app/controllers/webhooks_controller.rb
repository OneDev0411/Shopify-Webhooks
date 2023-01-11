# frozen_string_literal: true

class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_webhook

  #products/create, products/update
  def product
    product_id = params[:detail][:payload][:id]
    create_job_unless_exists('ShopWorker::UpdateProductIfUsedInOfferJob', [@myshopify_domain, product_id])
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
    collection_id = params[:detail][:payload][:id]
    create_job_unless_exists('ShopWorker::UpdateCollectionIfUsedInOfferJob', [@myshopify_domain, collection_id])
    head :ok and return
  end

  def order
    payload = params[:detail][:payload]
    discount_code = if payload['discount_codes'] && payload['discount_codes'][0]
      payload['discount_codes'][0]['code']
    else
      nil
    end
    order_opts = {
      'shopify_id' => payload['id'],
      'items' => (payload['line_items'] || []).map{|l| l['product_id'] }.compact.sort,
      'discount_code' => discount_code,
      'shopper_country' => payload['billing_address'].present? ? payload['billing_address']['country_code'] : nil,
      'referring_site' => payload['referring_site'],
      'orders_count' => payload['customer'].present? ? payload['customer']['orders_count'] : nil,
      'total' => payload['total_price'],
      'cart_token' => payload['cart_token']
    }
    Sidekiq::Client.push('class' => 'ShopWorker::RecordOrderJob', 'args' => [@myshopify_domain, order_opts], 'queue' => 'low', 'at' => Time.now.to_i + 10)
    head :ok and return
  end

  def app_uninstalled
    Sidekiq::Client.push('class' => 'ShopWorker::MarkShopAsCancelledJob', 'args' => [@myshopify_domain], 'queue' => 'low', 'at' => Time.now.to_i + 10)
    head :ok and return
  end

  def shop_update
    payload = params[:detail][:payload]
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
      @q.entries.each do |job|
        if job['class'] == job_class && job['args'].is_a?(Array) && job['args'] == args
          return
        end
      end
      puts "~~~~~~~~~~Pushing the job in Sidekiq~~~~~~~~~~~~"
      puts job_class
      puts args
      Sidekiq::Client.push('class' => job_class, 'args' => args, 'queue' => 'low', 'at' => Time.now.to_i)
    end

    def verify_webhook
      data = JSON.parse(request.body.read.to_s)

      @myshopify_domain = data['detail']['metadata']['X-Shopify-Shop-Domain']
      @q = Sidekiq::Queue.new('low')
    end
end
