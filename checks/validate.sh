#!usrbinenv bash
set -euo pipefail
pip3 install --quiet jsonschema
jsonschema -i contentjsoncards.json '{
  typeobject,
  properties{
    version{typestring},
    season{typestring},
    cards{typearray,items{
      typeobject,
      required[id,gender,context,items,assets],
      properties{
        id{typestring},
        gender{enum[male,female]},
        context{enum[daily,work,event]},
        items{typearray},
        assets{typeobject,required[flatlay,flatlay_outer]}
      }
    }}
  },
  required[version,season,cards]
}'
echo cards.json OK