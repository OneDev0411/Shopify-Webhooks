# frozen_string_literal: true
require 'rails_helper'

#    products_create POST /products/create(.:format)    webhooks#product
#    products_update POST /products/update(.:format)    webhooks#product
# collections_create POST /collections/create(.:format) webhooks#collection
# collections_update POST /collections/update(.:format) webhooks#collection
#    app_uninstalled POST /app/uninstalled(.:format)    webhooks#app_uninstalled
#      orders_create POST /orders/create(.:format)      webhooks#order
#        shop_update POST /shop/update(.:format)        webhooks#shop_update

RSpec.describe 'WebhooksController', type: :request do

  # This webhooks just push the payload to Redis: so, for our purpose, any JSON is valid
  let(:product_payload)  { load_payload 'product_create' }
  let(:collection_payload)  { load_payload 'collection_create' }
  let(:shopify_domain) { 'dev-store-manuel.myshopify.com' }

  describe 'POST#products_webhooks' do
    it 'receives JSON payload to create product' do
      shopify_headers = webhook_headers(shopify_domain, product_payload)

      post products_create_path, params: product_payload, headers: shopify_headers

      expect(response).to have_http_status :ok
    end

    it 'receives JSON payload to update product' do
      json_payload = load_payload 'product_create'
      shopify_headers = webhook_headers(shopify_domain, product_payload)

      post products_update_path, params: product_payload, headers: shopify_headers

      expect(response).to have_http_status :ok
    end
  end

  describe 'POST#collections_webhooks' do
    it 'receives JSON payload to create collection' do
      shopify_headers = webhook_headers(shopify_domain, collection_payload)

      post collections_create_path, params: collection_payload, headers: shopify_headers

      expect(response).to have_http_status :ok
    end

    it 'receives JSON payload to update collection' do
      shopify_headers = webhook_headers(shopify_domain, collection_payload)

      post collections_update_path, params: collection_payload, headers: shopify_headers

      expect(response).to have_http_status :ok
    end
  end

  describe 'POST#app_uninstalled_webhook' do
    it 'receives JSON payload to uninstall the app' do
      shopify_headers = webhook_headers(shopify_domain, collection_payload)

      post app_uninstalled_path, params: collection_payload, headers: shopify_headers

      expect(response).to have_http_status :ok
    end
  end

  describe 'POST#orders_create_webhook' do
    it 'receives JSON payload to create order' do
      shopify_headers = webhook_headers(shopify_domain, collection_payload)

      post orders_create_path, params: collection_payload, headers: shopify_headers

      expect(response).to have_http_status :ok
    end
  end

  describe 'POST#shop_update_webhook' do
    it 'receives JSON payload to create order' do
      shopify_headers = webhook_headers(shopify_domain, collection_payload)

      post shop_update_path, params: collection_payload, headers: shopify_headers

      expect(response).to have_http_status :ok
    end
  end

  describe '.check_duplicates?' do
    before do
      @controller = WebhooksController.new
    end
    it 'checks if CHECK_DUPLICATE_JOBS is set regardless of value' do
      result = @controller.instance_eval{ check_duplicates? }
      expect([true, false].include?(result)).to eq(true)
    end
  end
end
