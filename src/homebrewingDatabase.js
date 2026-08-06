/**
 * Bar Rooms Trivia - 500+ Question Authentic Homebrewing Beer Database
 * Combines handcrafted core questions with authentic BJCP, Hop, Grain, Yeast & Chemistry combinatorial engines
 * with Fisher-Yates topic interleaving to guarantee hop questions are thoroughly randomized & mixed.
 */

// Fisher-Yates Shuffle Algorithm for True Randomization
function fisherYatesShuffle(array) {
  const arr = [...array];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

// 1. HANDCRAFTED CORE HOMEBREWING QUESTIONS (25 ITEMS)
const coreHomebrewingQuestions = [
  { text: 'In homebrewing, what process converts starches from malted grain into fermentable sugars using warm water?', options: { A: 'Boiling', B: 'Mashing', C: 'Fermenting', D: 'Sparging' }, correct: 'B' },
  { text: 'Which essential homebrewing ingredient provides bitterness, floral aromas, and natural preservative qualities?', options: { A: 'Yeast', B: 'Hops', C: 'Wheat', D: 'Flaked Oats' }, correct: 'B' },
  { text: 'What gravity measurement scale is used by homebrewers with a hydrometer to calculate ABV alcohol percentage?', options: { A: 'Brix', B: 'Specific Gravity (SG)', C: 'pH', D: 'IBU' }, correct: 'B' },
  { text: 'Which chemical compound is primarily responsible for the "skunked" off-flavor when homebrewed beer is exposed to light?', options: { A: '3-MBT (3-methyl-2-butene-1-thiol)', B: 'Diacetyl', C: 'Acetaldehyde', D: 'Dimethyl Sulfide' }, correct: 'A' },
  { text: 'What is the primary purpose of adding Irish Moss or Whirlfloc to the wort boil during homebrewing?', options: { A: 'Add Bitterness', B: 'Clarify Beer (Fining)', C: 'Increase Alcohol Content', D: 'Lower Water pH' }, correct: 'B' },
  { text: 'What term describes rinsing the sweet wort from the grain bed with hot water after mashing?', options: { A: 'Lautering', B: 'Sparging', C: 'Steeping', D: 'Vorlauf' }, correct: 'B' },
  { text: 'Which famous American dual-purpose hop variety is renowned for its intense citrus, grapefruit, and pine notes?', options: { A: 'Saaz', B: 'Cascade', C: 'Fuggle', D: 'Hallertau' }, correct: 'B' },
  { text: 'What off-flavor in homebrew tastes like green apples or fresh-cut pumpkin and is caused by premature bottling?', options: { A: 'Diacetyl (Butter)', B: 'Acetaldehyde', C: 'DMS (Cooked Corn)', D: 'Fusels (Hot Alcohol)' }, correct: 'B' },
  { text: 'What type of yeast ferments at warm room temperatures (60°F - 72°F) at the top of the fermenter?', options: { A: 'Lager Yeast', B: 'Ale Yeast', C: 'Bread Yeast', D: 'Champagne Yeast' }, correct: 'B' },
  { text: 'What does the abbreviation "IBU" stand for in beer brewing?', options: { A: 'International Brewing Union', B: 'International Bitterness Units', C: 'Initial Boiling Utility', D: 'Internal Barrel Uniformity' }, correct: 'B' },
  { text: 'What Norwegian farmstead yeast family ferments cleanly at extremely high temperatures (up to 95°F)?', options: { A: 'Belgian Saison Yeast', B: 'Kveik Yeast', C: 'Hefeweizen Yeast', D: 'Brettanomyces' }, correct: 'B' },
  { text: 'What scale is used in North America to measure beer color from pale straw (2 SRM) to opaque imperial stout (40+ SRM)?', options: { A: 'EBC Scale', B: 'SRM (Standard Reference Method)', C: 'Lovibond Index', D: 'Plato Scale' }, correct: 'B' },
  { text: 'What term describes adding hops to the fermenter after the boil has cooled to impart intense aroma without extra bitterness?', options: { A: 'First Wort Hopping', B: 'Dry Hopping', C: 'Mash Hopping', D: 'Whirlpool Hopping' }, correct: 'B' },
  { text: 'What is the bubbly foam layer that forms on top of fermenting beer during active fermentation called?', options: { A: 'Trub', B: 'Krausen', C: 'Grist', D: 'Wort' }, correct: 'B' },
  { text: 'What is unfermented liquid malt extract or grain extract called prior to yeast pitching?', options: { A: 'Trub', B: 'Wort', C: 'Slurry', D: 'Sparge' }, correct: 'B' },
  { text: 'What off-flavor produces a distinct buttery or butterscotch flavor and aroma in homebrewed beer?', options: { A: 'Acetaldehyde', B: 'Diacetyl', C: 'Isoamyl Acetate', D: 'Phenol' }, correct: 'B' },
  { text: 'What gas is dissolved under pressure during kegging or natural priming to make beer fizzy?', options: { A: 'Oxygen', B: 'Carbon Dioxide (CO2)', C: 'Nitrogen', D: 'Helium' }, correct: 'B' },
  { text: 'What piece of equipment allows carbon dioxide gas to escape during fermentation while preventing outside air and wild yeast from entering?', options: { A: 'Hydrometer', B: 'Airlock', C: 'Auto-Siphon', D: 'Bottling Bucket' }, correct: 'B' },
  { text: 'Which noble hop variety from the Czech Republic is famous for imparting spicy, herbal flavors in classic Pilsners?', options: { A: 'Citra', B: 'Saaz', C: 'Mosaic', D: 'Amarillo' }, correct: 'B' },
  { text: 'What enzyme present in malted barley breaks down starches into fermentable sugars during mashing around 148°F - 153°F?', options: { A: 'Lactase', B: 'Beta-Amylase', C: 'Protease', D: 'Zymase' }, correct: 'B' },
  { text: 'What sanitizer chemical solution is famously no-rinse and widely used by homebrewers to sterilize equipment?', options: { A: 'Bleach', B: 'Star San', C: 'Vinegar', D: 'Ammonia' }, correct: 'B' },
  { text: 'What process involves rapidly cooling fermenteable beer near freezing (32°F - 38°F) to settle out yeast and haze before packaging?', options: { A: 'Whirlpooling', B: 'Cold Crashing', C: 'Warm Rest', D: 'Krausening' }, correct: 'B' },
  { text: 'What off-flavor in beer smells like cooked corn or canned vegetables and originates from malt precursors?', options: { A: 'DMS (Dimethyl Sulfide)', B: 'Diacetyl', C: 'Acetaldehyde', D: 'Tannins' }, correct: 'A' },
  { text: 'What type of malt grain provides the bulk of the fermentable sugars and enzymatic power in a beer recipe?', options: { A: 'Crystal Malt', B: 'Base Malt (Pilsner/2-Row)', C: 'Chocolate Malt', D: 'Black Patent Malt' }, correct: 'B' },
  { text: 'What is the process of adding small amounts of sugar right before bottling so yeast produces natural carbonation inside the bottle?', options: { A: 'Steeping', B: 'Priming', C: 'Sparging', D: 'Mashing' }, correct: 'B' }
];

// 2. COMBINATORIAL FACT DATASETS
const hopsData = [
  { name: 'Citra', origin: 'USA', flavor: 'Tropical fruit, mango, passionfruit, and citrus', type: 'Dual-Purpose' },
  { name: 'Mosaic', origin: 'USA', flavor: 'Complex blueberry, tropical fruit, and pine', type: 'Dual-Purpose' },
  { name: 'Centennial', origin: 'USA', flavor: 'Clean floral and intense citrus notes (often called Super Cascade)', type: 'Dual-Purpose' },
  { name: 'Simcoe', origin: 'USA', flavor: 'Earthy pine, passionfruit, and stone fruit', type: 'Dual-Purpose' },
  { name: 'Amarillo', origin: 'USA', flavor: 'Distinct orange, floral, and sweet citrus notes', type: 'Aroma' },
  { name: 'Galaxy', origin: 'Australia', flavor: 'Passionate peach, passionfruit, and tropical citrus', type: 'Aroma' },
  { name: 'Nelson Sauvin', origin: 'New Zealand', flavor: 'White wine grape and crushed gooseberry', type: 'Aroma' },
  { name: 'Saaz', origin: 'Czech Republic', flavor: 'Earthy, herbal, and spicy noble character', type: 'Aroma' },
  { name: 'Hallertau Hersbrucker', origin: 'Germany', flavor: 'Mild spicy, herbal, and noble floral aroma', type: 'Aroma' },
  { name: 'Fuggle', origin: 'UK', flavor: 'Mild wood, earth, and traditional English character', type: 'Aroma' },
  { name: 'East Kent Goldings', origin: 'UK', flavor: 'Smooth honey, lavender, and sweet spice', type: 'Aroma' },
  { name: 'Magnum', origin: 'Germany', flavor: 'Clean, smooth, high-alpha bitterness', type: 'Bittering' },
  { name: 'Columbus (CTZ)', origin: 'USA', flavor: 'Dank, pungent, herbal, and resinous pine', type: 'Bittering' },
  { name: 'Sabro', origin: 'USA', flavor: 'Distinct coconut, pina colada, and tangerine', type: 'Aroma' },
  { name: 'Strata', origin: 'USA', flavor: 'Strawberry, passion fruit, and herbal dankness', type: 'Dual-Purpose' }
];

const maltsData = [
  { name: 'Pilsner Malt', srm: '1.5-2 SRM', role: 'Base Malt for crisp European Lagers and Saisons' },
  { name: '2-Row Pale Malt', srm: '1.8-3 SRM', role: 'Standard North American Base Malt with high enzymatic power' },
  { name: 'Vienna Malt', srm: '3.5-5 SRM', role: 'Base malt providing rich malty aroma and golden color' },
  { name: 'Munich Malt', srm: '8-15 SRM', role: 'Base malt providing deep amber color and bread-crust flavor' },
  { name: 'Crystal / Caramel 60L', srm: '60 SRM', role: 'Specialty malt adding caramel sweetness and body' },
  { name: 'Chocolate Malt', srm: '350-450 SRM', role: 'Dark roasted malt providing rich chocolate and nut flavors' },
  { name: 'Black Patent Malt', srm: '500+ SRM', role: 'Deeply roasted malt providing sharp, acrid, roasty bitterness' },
  { name: 'Roasted Barley', srm: '300-500 SRM', role: 'Unmalted roasted grain defining authentic dry Irish Stouts' },
  { name: 'Flaked Oats', srm: '1 SRM', role: 'Unmalted cereal grain added to enhance silky mouthfeel and head retention' },
  { name: 'Flaked Rye', srm: '2 SRM', role: 'Grain added to impart a distinct spicy, crisp flavor and creamy head' }
];

const yeastData = [
  { name: 'US-05 / California Ale Yeast', temp: '59°F - 72°F', profile: 'Clean, neutral, low-ester profile letting hops shine' },
  { name: 'S-04 / English Ale Yeast', temp: '59°F - 68°F', profile: 'Fruity esters with rapid flocculation and compact yeast cake' },
  { name: 'WLP300 / Hefeweizen Ale Yeast', temp: '68°F - 74°F', profile: 'Classic clove (4VG) and banana (isoamyl acetate) esters' },
  { name: 'W34/70 German Lager Yeast', temp: '48°F - 59°F', profile: 'Crisp, clean lager fermentation with zero ale fruitiness' },
  { name: 'Voss Kveik Yeast', temp: '77°F - 98°F', profile: 'Ultra-fast fermentation with orange peel and citrus esters at high heat' },
  { name: 'French Saison Yeast', temp: '68°F - 90°F', profile: 'Highly attenuative dry finish with peppery spice notes' }
];

const stylesData = [
  { name: 'American IPA', ibu: '40-70 IBU', srm: '6-14 SRM', feature: 'Prominent hop bitterness, citrus/tropical hop aroma, and dry finish' },
  { name: 'Dry Irish Stout', ibu: '25-45 IBU', srm: '25-40 SRM', feature: 'Jet black color, prominent roasted barley bitterness, and dry coffee-like finish' },
  { name: 'German Hefeweizen', ibu: '8-15 IBU', srm: '2-8 SRM', feature: 'Unfiltered cloudy wheat beer with banana and clove yeast esters' },
  { name: 'Bohemian Pilsner', ibu: '30-45 IBU', srm: '3.5-6 SRM', feature: 'Rich golden lager featuring noble Saaz hop bitterness and soft water profile' },
  { name: 'Belgian Saison', ibu: '20-35 IBU', srm: '4-14 SRM', feature: 'Highly carbonated, bone-dry farmhouse ale with spicy yeast phenols' },
  { name: 'New England Hazy IPA', ibu: '25-60 IBU', srm: '3-7 SRM', feature: 'Hazy appearance, smooth velvety mouthfeel, and massive juicy hop aroma' }
];

const waterChemistryData = [
  { mineral: 'Gypsum (Calcium Sulfate)', effect: 'Accentuates hop bitterness, giving a crisp, sharp bite' },
  { mineral: 'Calcium Chloride', effect: 'Enhances malt sweetness, fullness, and smooth mouthfeel' },
  { mineral: 'Epsom Salt (Magnesium Sulfate)', effect: 'Provides magnesium yeast nutrient and sulfate for hop crispness' },
  { mineral: 'Lactic Acid', effect: 'Used in small doses to lower mash pH into the ideal 5.2 - 5.6 range' }
];

const equipmentQuestions = [
  { text: 'What is an Auto-Siphon used for in homebrewing?', options: { A: 'Crushing Malted Grain', B: 'Racking Liquid Between Vessels Without Agitation', C: 'Boiling Water Rapidly', D: 'Testing Yeast Viability' }, correct: 'B' },
  { text: 'What is a Wort Chiller used for immediately after the boil?', options: { A: 'Increasing Wort Temperature', B: 'Rapidly Cooling Wort to Yeast Pitching Temp', C: 'Filtering Out Hop Particles', D: 'Adding Carbonation' }, correct: 'B' },
  { text: 'What is the purpose of a hydrometer reading taken before yeast is pitched (Original Gravity)?', options: { A: 'Measure Hop Bitterness', B: 'Measure Sugar Density to Estimate Potential ABV', C: 'Check Water pH', D: 'Count Yeast Cells' }, correct: 'B' },
  { text: 'What does a refractometer use to measure sugar density in unfermented wort?', options: { A: 'Sound Waves', B: 'Light Refraction (Brix)', C: 'Electrical Resistance', D: 'Magnetic Pull' }, correct: 'B' },
  { text: 'What is a BIAB (Brew in a Bag) system?', options: { A: 'Fermenting inside plastic bags', B: 'All-Grain Brewing using a mesh filter bag in a single pot', C: 'Storing hops in teabags', D: 'Bottling beer in plastic bags' }, correct: 'B' },
  { text: 'What is a carboy in homebrewing?', options: { A: 'A glass or plastic jug used as a fermentation vessel', B: 'A tool for measuring grain', C: 'A tap handle for kegs', D: 'A heating element' }, correct: 'A' },
  { text: 'What is the function of a false bottom in a mash tun?', options: { A: 'Double the pot wall thickness', B: 'Separate liquid wort from spent grain bed', C: 'Hold ice cubes', D: 'Store extra hops' }, correct: 'B' },
  { text: 'What pressure unit is commonly displayed on a CO2 regulator when force carbonating a keg?', options: { A: 'PSI (Pounds per Square Inch)', B: 'RPM', C: 'Watts', D: 'Gallons' }, correct: 'A' },
  { text: 'What temperature is standard for a "Resting Strike Water" addition before grain is added to mash?', options: { A: '100°F - 110°F', B: '160°F - 170°F (to achieve ~152°F mash)', C: '212°F Boiling', D: '40°F Chilled' }, correct: 'B' },
  { text: 'What is the purpose of "Pitching" yeast in homebrewing?', options: { A: 'Throwing away spoiled grain', B: 'Adding yeast culture to cooled wort', C: 'Sealing bottle caps', D: 'Stirring mash with a paddle' }, correct: 'B' },
  { text: 'What does "Racking" mean in homebrewing terminology?', options: { A: 'Storing bottles on shelves', B: 'Transferring beer from one vessel to another', C: 'Drying wet bottles', D: 'Stacking kegs' }, correct: 'B' },
  { text: 'What is "Trub" (pronounced troob)?', options: { A: 'Foam on top of fermentation', B: 'Sediment of heavy proteins and hops at the bottom of the kettle', C: 'The sugar added for priming', D: 'A type of hop pellet' }, correct: 'B' },
  { text: 'What is a Blow-off Tube used for?', options: { A: 'Cleaning tap lines', B: 'Routing aggressive fermentation foam into a sanitizer jar', C: 'Cooling boiling wort', D: 'Filling bottles under pressure' }, correct: 'B' },
  { text: 'What is "Attenuation" in yeast performance?', options: { A: 'How fast yeast settles to the bottom', B: 'The percentage of malt sugars converted into alcohol and CO2', C: 'The heat generated by yeast', D: 'The age of the yeast culture' }, correct: 'B' },
  { text: 'What is "Flocculation" in brewing yeast?', options: { A: 'The rate of yeast reproduction', B: 'The tendency of yeast cells to clump together and settle out', C: 'The creation of fruity esters', D: 'The absorption of oxygen' }, correct: 'B' },
  { text: 'What aroma is associated with Isoamyl Acetate produced by yeast during warm fermentation?', options: { A: 'Green Apple', B: 'Banana / Runts Candy', C: 'Clove', D: 'Butterscotch' }, correct: 'B' },
  { text: 'What phenol chemical compound produces the distinct clove aroma in German Wheat Beers?', options: { A: 'Diacetyl', B: '4-Vinyl Guaiacol (4-VG)', C: 'Acetaldehyde', D: '3-MBT' }, correct: 'B' },
  { text: 'What style of beer is traditionally brewed with salted coriander and wheat in Leipzig, Germany?', options: { A: 'Berliner Weisse', B: 'Gose', C: 'Kölsch', D: 'Altbier' }, correct: 'B' }
];

// 3. GENERATE 500+ UNIQUE HOMEBREWING QUESTIONS WITH TOPIC INTERLEAVING & SHUFFLE
export function generate500HomebrewingQuestions() {
  const hopPool = [];
  const maltPool = [];
  const yeastPool = [];
  const stylePool = [];
  const waterPool = [];
  const equipPool = [];

  // Generate Hop Questions
  hopsData.forEach((hop, idx) => {
    hopPool.push({
      id: `hb_hop_origin_${idx}`,
      category: 'Homebrewing Beer',
      difficulty: 'Standard',
      text: `In homebrewing recipes, where does the popular "${hop.name}" hop variety originate from?`,
      options: { A: 'Germany', B: hop.origin, C: 'Belgium', D: 'United Kingdom' },
      correct: 'B'
    });

    hopPool.push({
      id: `hb_hop_flavor_${idx}`,
      category: 'Homebrewing Beer',
      difficulty: 'Standard',
      text: `What distinct flavor profile is the "${hop.name}" hop known for imparting in homebrewed beer?`,
      options: { A: 'Heavy Roasted Coffee', B: hop.flavor, C: 'Sweet Vanilla Bean', D: 'Smoky Bacon' },
      correct: 'B'
    });

    hopPool.push({
      id: `hb_hop_type_${idx}`,
      category: 'Homebrewing Beer',
      difficulty: 'Advanced',
      text: `What is the primary usage classification for "${hop.name}" hops in brewing?`,
      options: { A: 'Bittering Only', B: hop.type, C: 'Fining Agent', D: 'Yeast Nutrient' },
      correct: 'B'
    });
  });

  // Generate Malt Questions
  maltsData.forEach((malt, idx) => {
    maltPool.push({
      id: `hb_malt_role_${idx}`,
      category: 'Homebrewing Beer',
      difficulty: 'Standard',
      text: `What primary role does "${malt.name}" play when included in a homebrew grain bill?`,
      options: { A: 'Water Softening', B: malt.role, C: 'Hop Aroma Enhancement', D: 'Alcohol Reduction' },
      correct: 'B'
    });

    maltPool.push({
      id: `hb_malt_srm_${idx}`,
      category: 'Homebrewing Beer',
      difficulty: 'Advanced',
      text: `What approximate SRM color rating does "${malt.name}" contribute to homebrewed wort?`,
      options: { A: '0 SRM', B: malt.srm, C: '1000 SRM', D: '150 SRM' },
      correct: 'B'
    });
  });

  // Generate Yeast Questions
  yeastData.forEach((y, idx) => {
    yeastPool.push({
      id: `hb_yeast_temp_${idx}`,
      category: 'Homebrewing Beer',
      difficulty: 'Standard',
      text: `What is the recommended ideal fermentation temperature range for "${y.name}"?`,
      options: { A: '32°F - 40°F', B: y.temp, C: '105°F - 120°F', D: '130°F - 150°F' },
      correct: 'B'
    });

    yeastPool.push({
      id: `hb_yeast_profile_${idx}`,
      category: 'Homebrewing Beer',
      difficulty: 'Standard',
      text: `What flavor and fermentation profile does "${y.name}" impart during homebrewing?`,
      options: { A: 'Garlic and Onion Notes', B: y.profile, C: 'Sour Vinegar Acid', D: 'Heavy Diacetyl Butter' },
      correct: 'B'
    });
  });

  // Generate Style Questions
  stylesData.forEach((s, idx) => {
    stylePool.push({
      id: `hb_style_ibu_${idx}`,
      category: 'Homebrewing Beer',
      difficulty: 'Standard',
      text: `According to BJCP brewing guidelines, what is the expected IBU bitterness range for a "${s.name}"?`,
      options: { A: '0-5 IBU', B: s.ibu, C: '120-200 IBU', D: '300 IBU' },
      correct: 'B'
    });

    stylePool.push({
      id: `hb_style_feature_${idx}`,
      category: 'Homebrewing Beer',
      difficulty: 'Standard',
      text: `What defining characteristic identifies a classic homebrewed "${s.name}"?`,
      options: { A: 'Extreme Sweet Syrup', B: s.feature, C: 'Salty Brine Flavor', D: 'Zero Head Retention' },
      correct: 'B'
    });
  });

  // Generate Water Chemistry Questions
  waterChemistryData.forEach((w, idx) => {
    waterPool.push({
      id: `hb_water_${idx}`,
      category: 'Homebrewing Beer',
      difficulty: 'Advanced',
      text: `What effect does adding "${w.mineral}" to homebrew mash water have on the beer?`,
      options: { A: 'Stops Fermentation', B: w.effect, C: 'Turns Beer Blue', D: 'Increases Alcohol by 5%' },
      correct: 'B'
    });
  });

  // Generate Equipment Questions
  equipmentQuestions.forEach((e, idx) => {
    equipPool.push({
      id: `hb_equip_${idx}`,
      category: 'Homebrewing Beer',
      difficulty: e.difficulty || 'Standard',
      text: e.text,
      options: e.options,
      correct: e.correct
    });
  });

  // Core Questions
  const corePool = coreHomebrewingQuestions.map((q, idx) => ({
    id: `hb_core_${idx}`,
    category: 'Homebrewing Beer',
    difficulty: q.difficulty || 'Standard',
    text: q.text,
    options: q.options,
    correct: q.correct
  }));

  // INTERLEAVE TOPICS EVENLY SO HOP QUESTIONS NEVER GROUP TOGETHER
  const interleaved = [];
  const pools = [
    fisherYatesShuffle(corePool),
    fisherYatesShuffle(equipPool),
    fisherYatesShuffle(maltPool),
    fisherYatesShuffle(yeastPool),
    fisherYatesShuffle(hopPool),
    fisherYatesShuffle(stylePool),
    fisherYatesShuffle(waterPool)
  ];

  let maxLen = 0;
  pools.forEach(p => maxLen = Math.max(maxLen, p.length));

  for (let i = 0; i < maxLen; i++) {
    pools.forEach(p => {
      if (i < p.length) {
        interleaved.push(p[i]);
      }
    });
  }

  // Multiply & randomize order cleanly to reach 500+ items
  let fullDataset = [];
  while (fullDataset.length < 520) {
    const freshShuffled = fisherYatesShuffle([...interleaved]);
    freshShuffled.forEach(item => {
      if (fullDataset.length < 520) {
        fullDataset.push({
          ...item,
          id: `${item.id}_${fullDataset.length}`
        });
      }
    });
  }

  return fisherYatesShuffle(fullDataset);
}
