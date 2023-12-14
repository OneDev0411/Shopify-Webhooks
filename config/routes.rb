Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  post '/products/create' => 'webhooks#product'
  post '/products/update' => 'webhooks#product'
  post '/products/delete' => 'webhooks#product_deleted'
  post '/collections/create' => 'webhooks#collection'
  post '/collections/update' => 'webhooks#collection'
  post '/app/uninstalled' => 'webhooks#app_uninstalled'
  post '/orders/create' => 'webhooks#order'
  post '/shop/update' => 'webhooks#shop_update'
end
