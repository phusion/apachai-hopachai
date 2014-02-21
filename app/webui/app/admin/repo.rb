ActiveAdmin.register Repo do
  permit_params :owner_id, :name, :url, :public_key, :private_key, :public_ssh_key, :private_ssh_key

  index do
    selectable_column
    id_column
    column :long_name
    column :url
    actions
  end

  form do |f|
    f.inputs "Repository Details" do
      f.input :owner
      f.input :name
      f.input :url
      if !f.object.new_record?
        f.input :public_key
        f.input :private_key
        f.input :public_ssh_key
        f.input :private_ssh_key
      end
    end
    f.actions
  end
end
