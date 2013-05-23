ArchivesSpace::Application.routes.draw do

  get "import/index"
  post "import/upload"

  match 'login' => "session#login", :via => :post
  match 'logout' => "session#logout", :via => :get

  match 'repositories/select' => 'repositories#select', :via => [:post]
  resources :repositories
  match 'repositories/:id' => 'repositories#update', :via => [:post]
  match 'repositories/:id/delete' => 'repositories#delete', :via => [:post]

  match 'users/manage_access' => 'users#manage_access', :via => [:get]
  match 'users/:id/edit_groups' => 'users#edit_groups', :via => [:get]
  match 'users/:id/edit' => 'users#edit', :via => [:get]
  match 'users/:id/update_groups' => 'users#update_groups', :via => [:post]
  match 'users/new' => 'users#new', :via => [:get]
  match 'users/complete' => 'users#complete', :via => [:get]
  match 'users/:id' => 'users#show', :via => [:get]
  match 'users/:id' => 'users#update', :via => [:post]
  match 'users/:id/delete' => 'users#delete', :via => [:post]
  resources :users

  resources :groups
  match 'groups/:id' => 'groups#update', :via => [:post]
  match 'groups/:id/delete' => 'groups#delete', :via => [:post]

  resources :accessions
  match 'accessions/:id' => 'accessions#update', :via => [:post]
  match 'accessions/:id/suppress' => 'accessions#suppress', :via => [:post]
  match 'accessions/:id/unsuppress' => 'accessions#unsuppress', :via => [:post]
  match 'accessions/:id/delete' => 'accessions#delete', :via => [:post]

  match 'archival_objects/:id/transfer' => 'archival_objects#transfer', :via => [:post]
  resources :archival_objects
  match 'archival_objects/:id' => 'archival_objects#update', :via => [:post]
  match 'archival_objects/:id/delete' => 'archival_objects#delete', :via => [:post]
  match 'archival_objects/:id/parent' => 'archival_objects#parent', :via => [:post]
  match 'archival_objects/:id/rde' => 'archival_objects#rde', :via => [:get]
  match 'archival_objects/:id/add_children' => 'archival_objects#add_children', :via => [:post]

  resources :digital_objects
  match 'digital_objects/:id/download_dc' => 'exports#download_dc', :via => [:get]
  match 'digital_objects/:id/download_mets' => 'exports#download_mets', :via => [:get]
  match 'digital_objects/:id/download_mods' => 'exports#download_mods', :via => [:get]
  match 'digital_objects/:id' => 'digital_objects#update', :via => [:post]
  match 'digital_objects/:id/delete' => 'digital_objects#delete', :via => [:post]
  match 'digital_objects/:id/publish' => 'digital_objects#publish', :via => [:post]

  resources :digital_object_components
  match 'digital_object_components/:id' => 'digital_object_components#update', :via => [:post]
  match 'digital_object_components/:id/parent' => 'digital_object_components#parent', :via => [:post]
  match 'digital_object_components/:id/delete' => 'digital_object_components#delete', :via => [:post]

  resources :resources
  match 'resources/:id/container_labels' => 'exports#container_labels', :via => [:get]
  match 'resources/:id/download_marc' => 'exports#download_marc', :via => [:get]
  match 'resources/:id/download_ead' => 'exports#download_ead', :via => [:get]
  match 'resources/:id' => 'resources#update', :via => [:post]
  match 'resources/:id/delete' => 'resources#delete', :via => [:post]
  match 'resources/:id/rde' => 'resources#rde', :via => [:get]
  match 'resources/:id/add_children' => 'resources#add_children', :via => [:post]
  match 'resources/:id/publish' => 'resources#publish', :via => [:post]

  resources :classifications
  match 'classifications/:id' => 'classifications#update', :via => [:post]
  match 'classifications/:id/delete' => 'classifications#delete', :via => [:post]

  resources :classification_terms
  match 'classification_terms/:id' => 'classification_terms#update', :via => [:post]
  match 'classification_terms/:id/delete' => 'classification_terms#delete', :via => [:post]
  match 'classification_terms/:id/parent' => 'classification_terms#parent', :via => [:post]

  resources :subjects
  match 'subjects/:id' => 'subjects#update', :via => [:post]
  match 'subjects/terms/complete' => 'subjects#terms_complete', :via => [:get]
  match 'subjects/:id/delete' => 'subjects#delete', :via => [:post]

  resources :locations
  match 'locations/:id' => 'locations#update', :via => [:post]

  resources :events
  match 'events/:id' => 'events#update', :via => [:post]
  match 'events/:id/delete' => 'events#delete', :via => [:post]

  match 'agents/contact_form' => 'agents#contact_form', :via => [:get]
  match 'agents/:type/name_form' => 'agents#name_form', :via => [:get]
  match 'agents/:type/create' => 'agents#create', :via => [:post]
  match 'agents/:type/new' => 'agents#new', :via => [:get]
  match 'agents/:type/:id/edit' => 'agents#edit', :via => [:get]
  match 'agents/:type/:id/update' => 'agents#update', :via => [:post]
  match 'agents/:type/:id/download_eac' => 'exports#download_eac', :via => [:get]
  match 'agents/:type/:id' => 'agents#show', :via => [:get]
  match 'agents' => 'agents#index', :via => [:get]
  match 'agents/:type/:id/delete' => 'agents#delete', :via => [:post]


  resources :collection_management

  match 'test/shutdown' => 'tests#shutdown', :via => [:get]

  match 'search' => 'search#do_search', :via => [:get]

  match 'resolve/edit' => 'resolver#resolve_edit', :via => [:get]
  match 'resolve/readonly' => 'resolver#resolve_readonly', :via => [:get]

  match 'enumerations/list' => 'enumerations#list', :via => [:get]
  match 'enumerations/delete' => 'enumerations#delete', :via => [:get]
  match 'enumerations/set_default/:id' => 'enumerations#set_default', :via => [:post] 
  match 'enumerations/destroy/:id' => 'enumerations#destroy', :via => [:post]
  match 'enumerations/merge/:id' => 'enumerations#merge', :via => [:post]
  resources :enumerations

  match 'reports' => 'reports#index', :via => [:get]
  match 'reports/download' => 'reports#download', :via => [:post]

  root :to => 'welcome#index'

end
