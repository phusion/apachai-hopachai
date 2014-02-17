ActiveAdmin.register User do
  permit_params :username, :email, :admin, :password, :password_confirmation

  index do
    selectable_column
    id_column
    column :username
    column :email
    column :admin?
    actions
  end

  filter :email
  filter :current_sign_in_at
  filter :sign_in_count
  filter :created_at

  form do |f|
    f.inputs "User Details" do
      f.input :username
      f.input :email
      f.input :admin
      f.input :password
      f.input :password_confirmation
    end
    f.actions
  end

end
