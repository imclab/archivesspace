{
  :schema => {
    "$schema" => "http://www.archivesspace.org/archivesspace.json",
    "type" => "object",
    "uri" => "/users",
    "properties" => {
      "uri" => {"type" => "string", "required" => false},

      "username" => {"type" => "string", "maxLength" => 255, "ifmissing" => "error", "minLength" => 1},
      "name" => {"type" => "string", "maxLength" => 255, "ifmissing" => "error", "minLength" => 1},

      "permissions" => {
        "type" => "object",
        "readonly" => true,
      },
      
      "email" => {"type" => "string", "maxLength" => 255},
      "first_name" => {"type" => "string", "maxLength" => 255},
      "last_name" => {"type" => "string", "maxLength" => 255},
      "telephone" => {"type" => "string", "maxLength" => 255},
      "title" => {"type" => "string", "maxLength" => 255},
      "department" => {"type" => "string", "maxLength" => 255},
      "additional_contact" => {"type" => "string", "maxLength" => 32672},
      
      "agent_record" => {
        "type" => "object",
        "readonly" => true,
        "subtype" => "ref",
        "properties" => {
          "ref" => {
            "type" => [{"type" => "JSONModel(:agent_person) uri"}, {"type" => "JSONModel(:agent_software) uri"}]
            },
            "_resolved" => {
              "type" => "object",
              "readonly" => "true"
            }
          }
      }
    },

    "additionalProperties" => false,
  },
}
