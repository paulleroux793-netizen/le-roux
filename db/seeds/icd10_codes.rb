# Seed common dental ICD-10 codes (SA / WHO ICD-10). Idempotent. Covers K00-K14 oral cavity +
# Z01.20 routine dental exam + common trauma codes (S00-S09). Curated from the practice's
# real GoodX estimates and standard SADA references; the dentist can edit/extend in-app.
#   bundle exec rails runner db/seeds/icd10_codes.rb
codes = [
  # K00 — tooth development/eruption
  [ "K00.0", "Anodontia", "K00 Development" ],
  [ "K00.6", "Disturbances in tooth eruption", "K00 Development" ],
  [ "K00.7", "Teething syndrome", "K00 Development" ],

  # K01 — impacted/embedded teeth
  [ "K01.0", "Embedded teeth", "K01 Impacted" ],
  [ "K01.1", "Impacted teeth", "K01 Impacted" ],

  # K02 — dental caries
  [ "K02.0", "Caries limited to enamel", "K02 Caries" ],
  [ "K02.1", "Caries of dentine", "K02 Caries" ],
  [ "K02.2", "Caries of cementum", "K02 Caries" ],
  [ "K02.3", "Arrested dental caries", "K02 Caries" ],
  [ "K02.5", "Caries on pit and fissure surface", "K02 Caries" ],
  [ "K02.6", "Caries on smooth surface", "K02 Caries" ],
  [ "K02.8", "Other dental caries", "K02 Caries" ],
  [ "K02.9", "Dental caries, unspecified", "K02 Caries" ],

  # K03 — hard tissue (non-caries)
  [ "K03.0", "Excessive attrition of teeth", "K03 Hard tissue" ],
  [ "K03.1", "Abrasion of teeth", "K03 Hard tissue" ],
  [ "K03.2", "Erosion of teeth", "K03 Hard tissue" ],
  [ "K03.3", "Pathological resorption of teeth", "K03 Hard tissue" ],
  [ "K03.6", "Deposits (accretions) on teeth", "K03 Hard tissue" ],
  [ "K03.7", "Posteruptive colour changes of dental hard tissues", "K03 Hard tissue" ],
  [ "K03.8", "Other specified diseases of hard tissues", "K03 Hard tissue" ],

  # K04 — pulp / periapical
  [ "K04.0", "Pulpitis", "K04 Pulpal/periapical" ],
  [ "K04.1", "Necrosis of pulp", "K04 Pulpal/periapical" ],
  [ "K04.4", "Acute apical periodontitis of pulpal origin", "K04 Pulpal/periapical" ],
  [ "K04.5", "Chronic apical periodontitis", "K04 Pulpal/periapical" ],
  [ "K04.6", "Periapical abscess with sinus", "K04 Pulpal/periapical" ],
  [ "K04.7", "Periapical abscess without sinus", "K04 Pulpal/periapical" ],
  [ "K04.8", "Radicular cyst", "K04 Pulpal/periapical" ],

  # K05 — gingival / periodontal
  [ "K05.0", "Acute gingivitis", "K05 Gingival/periodontal" ],
  [ "K05.1", "Chronic gingivitis", "K05 Gingival/periodontal" ],
  [ "K05.2", "Acute periodontitis", "K05 Gingival/periodontal" ],
  [ "K05.3", "Chronic periodontitis", "K05 Gingival/periodontal" ],
  [ "K05.4", "Periodontosis", "K05 Gingival/periodontal" ],
  [ "K05.5", "Other periodontal diseases", "K05 Gingival/periodontal" ],
  [ "K05.6", "Periodontal disease, unspecified", "K05 Gingival/periodontal" ],

  # K06 — gingival / alveolar ridge
  [ "K06.0", "Gingival recession", "K06 Gingival/alveolar" ],
  [ "K06.1", "Gingival enlargement", "K06 Gingival/alveolar" ],
  [ "K06.8", "Other specified disorders of gingiva and edentulous alveolar ridge", "K06 Gingival/alveolar" ],

  # K07 — dentofacial anomalies / malocclusion
  [ "K07.0", "Major anomalies of jaw size", "K07 Dentofacial" ],
  [ "K07.3", "Anomalies of tooth position", "K07 Dentofacial" ],
  [ "K07.4", "Malocclusion, unspecified", "K07 Dentofacial" ],
  [ "K07.6", "Temporomandibular joint disorders", "K07 Dentofacial" ],

  # K08 — teeth/supporting structures
  [ "K08.0", "Exfoliation of teeth due to systemic causes", "K08 Teeth/supporting" ],
  [ "K08.1", "Loss of teeth due to accident, extraction or local periodontal disease", "K08 Teeth/supporting" ],
  [ "K08.2", "Atrophy of edentulous alveolar ridge", "K08 Teeth/supporting" ],
  [ "K08.3", "Retained dental root", "K08 Teeth/supporting" ],
  [ "K08.8", "Other specified disorders of teeth and supporting structures", "K08 Teeth/supporting" ],
  [ "K08.9", "Disorder of teeth and supporting structures, unspecified", "K08 Teeth/supporting" ],

  # K09 — oral cysts
  [ "K09.0", "Developmental odontogenic cysts", "K09 Cysts" ],

  # K12 — stomatitis
  [ "K12.0", "Recurrent oral aphthae", "K12 Stomatitis" ],

  # K14 — tongue
  [ "K14.0", "Glossitis", "K14 Tongue" ],

  # Z01 — examination
  [ "Z01.20", "Encounter for dental examination and cleaning", "Z01 Examination" ],

  # S00–S09 — head trauma (dental relevant)
  [ "S02.5", "Fracture of tooth", "S00 Trauma" ],
  [ "S03.2", "Dislocation of tooth", "S00 Trauma" ]
]

created = 0
codes.each do |code, desc, cat|
  rec = Icd10Code.find_or_initialize_by(code: code)
  rec.description = desc; rec.category = cat
  rec.save! && (created += 1) if rec.new_record? || rec.changed?
end
puts "icd10_codes: #{Icd10Code.count} total (#{created} upserted this run)"
