resources :documents, only: [:destroy]

get '/d/:id', to: 'documents#download', as: 'short_doc'
