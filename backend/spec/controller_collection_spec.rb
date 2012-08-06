require 'spec_helper'

describe 'Collections controller' do

  before(:each) do
    @repo = make_test_repo
  end


  it "lets you create a collection and get it back" do
    post "#{@repo}/collections", params = JSONModel(:collection).
      from_hash({"title" => "a collection"}).to_json

    last_response.should be_ok
    created = JSON(last_response.body)

    get "#{@repo}/collections/#{created["id"]}"

    collection = JSON(last_response.body)

    collection["title"].should eq("a collection")
  end


  it "lets you manipulate the record hierarchy" do
    post "#{@repo}/collections", params = JSONModel(:collection).
      from_hash({
                  "id_0" => "1234",
                  "title" => "a collection",
                }).to_json

    last_response.should be_ok
    collection = JSON(last_response.body)


    ids = []
    ["earth", "australia", "canberra"].each do |name|
      ao = JSONModel(:archival_object).from_hash({
                                                   "id_0" => name,
                                                   "title" => "archival object: #{name}",
                                                 })
      if not ids.empty?
        ao.parent = "#{@repo}/archival_objects/#{ids.last}"
      end

      ao.collection = "#{@repo}/collections/#{collection['id']}"


      post "#{@repo}/archival_objects", params = ao.to_json
      last_response.should be_ok
      created = JSON(last_response.body)

      ids << created["id"]
    end


    get "#{@repo}/collections/#{collection['id']}/tree"
    last_response.should be_ok
    tree = JSON(last_response.body)

    archival_objects = "#{@repo}/archival_objects/"
    tree.should eq({
                     "archival_object" => "#{archival_objects}#{ids[0]}",
                     "title" => "archival object: earth",
                     "children" => [
                                    {
                                      "archival_object" => "#{archival_objects}#{ids[1]}",
                                      "title" => "archival object: australia",
                                      "children" => [
                                                     {
                                                       "archival_object" => "#{archival_objects}#{ids[2]}",
                                                       "title" => "archival object: canberra",
                                                       "children" => []
                                                     }
                                                    ]
                                    }
                                   ]
                   })


    # Now turn it on its head
    changed = {
      "archival_object" => "#{archival_objects}#{ids[2]}",
      "title" => "archival object: canberra",
      "children" => [
                     {
                       "archival_object" => "#{archival_objects}#{ids[1]}",
                       "title" => "archival object: australia",
                       "children" => [
                                      {
                                        "archival_object" => "#{archival_objects}#{ids[0]}",
                                        "title" => "archival object: earth",
                                        "children" => []
                                      }
                                     ]
                     }
                    ]
    }

    post "#{@repo}/collections/#{collection['id']}/tree", JSON(changed)
    last_response.should be_ok

    get "#{@repo}/collections/#{collection['id']}/tree"
    last_response.should be_ok
    tree = JSON(last_response.body)

    tree.should eq(changed)
  end



  it "lets you update a collection" do
    collection = JSONModel(:collection).from_hash({
                                                    "title" => "a collection",
                                                  })

    post "#{@repo}/collections", params = collection.to_json

    last_response.should be_ok
    created = JSON(last_response.body)

    collection.title = "an updated collection"

    post "#{@repo}/collections/#{created['id']}", params = collection.to_json

    get "#{@repo}/collections/#{created["id"]}"

    collection = JSON(last_response.body)

    collection["title"].should eq("an updated collection")
  end


end
