Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  post '/products/create' => 'webhooks#product'
  post '/products/update' => 'webhooks#product'
  post '/products/delete' => 'webhooks#delete_product'
  post '/collections/create' => 'webhooks#collection'
  post '/collections/update' => 'webhooks#collection'
  post '/app/uninstalled' => 'webhooks#app_uninstalled'
  post '/orders/create' => 'webhooks#order'
  post '/shop/update' => 'webhooks#shop_update'
  post '/theme/publish' => 'webhooks#theme_publish'
  post '/theme/update' => 'webhooks#theme_publish'
end
