ActiveAdmin.register Project do
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
  end
end
