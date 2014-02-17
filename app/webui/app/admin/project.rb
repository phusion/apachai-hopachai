ActiveAdmin.register Project do
  permit_params :owner_id, :name, :repo_url, :public_key, :private_key

  form do |f|
    f.inputs "User Details" do
      f.input :owner
      f.input :name
      f.input :repo_url
      if !f.object.new_record?
          f.input :public_key
          f.input :private_key
      end
    end
    f.actions
  end
end
