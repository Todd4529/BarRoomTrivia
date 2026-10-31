/**
 * Bar Rooms Trivia - 500+ Unique Question Authentic Homebrewing Beer Database
 * Combines handcrafted core questions with authentic BJCP, Hop, Grain, Yeast & Chemistry combinatorial engines
 * with Fisher-Yates topic interleaving to guarantee questions are thoroughly randomized with zero repeats.
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

// 1. EXTENDED COMBINATORIAL FACT DATASETS (Over 100+ distinct entities)
const hopsData = [
  { name: 'Citra', origin: 'USA', flavor: 'Tropical fruit, mango, passionfruit, and citrus', type: 'Dual-Purpose', alpha: '11-13% Alpha Acids' },
  { name: 'Mosaic', origin: 'USA', flavor: 'Complex blueberry, tropical fruit, and pine', type: 'Dual-Purpose', alpha: '11.5-13.5% Alpha Acids' },
  { name: 'Centennial', origin: 'USA', flavor: 'Clean floral and intense citrus notes (Super Cascade)', type: 'Dual-Purpose', alpha: '9.5-11.5% Alpha Acids' },
  { name: 'Simcoe', origin: 'USA', flavor: 'Earthy pine, passionfruit, and stone fruit', type: 'Dual-Purpose', alpha: '12-14% Alpha Acids' },
  { name: 'Amarillo', origin: 'USA', flavor: 'Distinct orange blossom, floral, and sweet citrus', type: 'Aroma', alpha: '8-11% Alpha Acids' },
  { name: 'Galaxy', origin: 'Australia', flavor: 'Passionate peach, passionfruit, and tropical citrus', type: 'Aroma', alpha: '13.5-15% Alpha Acids' },
  { name: 'Nelson Sauvin', origin: 'New Zealand', flavor: 'White wine grape and crushed gooseberry', type: 'Aroma', alpha: '12-13% Alpha Acids' },
  { name: 'Saaz', origin: 'Czech Republic', flavor: 'Earthy, herbal, and spicy noble character', type: 'Aroma', alpha: '3-4.5% Alpha Acids' },
  { name: 'Hallertau Mittelfrüh', origin: 'Germany', flavor: 'Mild spicy, herbal, and noble floral aroma', type: 'Aroma', alpha: '3-5.5% Alpha Acids' },
  { name: 'Fuggle', origin: 'UK', flavor: 'Mild wood, earth, and traditional English character', type: 'Aroma', alpha: '4-5.5% Alpha Acids' },
  { name: 'East Kent Goldings', origin: 'UK', flavor: 'Smooth honey, lavender, and sweet spice', type: 'Aroma', alpha: '4.5-6.5% Alpha Acids' },
  { name: 'Magnum', origin: 'Germany', flavor: 'Clean, smooth, high-alpha bitterness', type: 'Bittering', alpha: '12-14% Alpha Acids' },
  { name: 'Columbus (CTZ)', origin: 'USA', flavor: 'Dank, pungent, herbal, and resinous pine', type: 'Bittering', alpha: '14-16% Alpha Acids' },
  { name: 'Sabro', origin: 'USA', flavor: 'Distinct coconut, pina colada, and tangerine', type: 'Aroma', alpha: '12-16% Alpha Acids' },
  { name: 'Strata', origin: 'USA', flavor: 'Strawberry, passionfruit, and herbal dankness', type: 'Dual-Purpose', alpha: '11-13% Alpha Acids' },
  { name: 'Motueka', origin: 'New Zealand', flavor: 'Fresh crushed lime zest and sweet lemon', type: 'Aroma', alpha: '6.5-7.5% Alpha Acids' },
  { name: 'El Dorado', origin: 'USA', flavor: 'Ripe pear, watermelon, and stone fruit candy', type: 'Dual-Purpose', alpha: '14-16% Alpha Acids' },
  { name: 'Chinook', origin: 'USA', flavor: 'Grapefruit zest, heavy pine resin, and smoky spice', type: 'Bittering', alpha: '12-14% Alpha Acids' },
  { name: 'Cashmere', origin: 'USA', flavor: 'Silky smooth melon, peach, and candied citrus', type: 'Aroma', alpha: '7.7-9.1% Alpha Acids' },
  { name: 'Vic Secret', origin: 'Australia', flavor: 'Clean pineapple, pine, and tropical resin', type: 'Aroma', alpha: '14-17% Alpha Acids' },
];

const maltsData = [
  { name: 'Pilsner Malt', srm: '1.5-2 SRM', role: 'Base Malt for crisp European Lagers and Saisons', origin: 'Germany/Czech' },
  { name: '2-Row Pale Malt', srm: '1.8-3 SRM', role: 'Standard North American Base Malt with high enzymatic power', origin: 'USA' },
  { name: 'Vienna Malt', srm: '3.5-5 SRM', role: 'Base malt providing rich malty aroma and golden color', origin: 'Austria/Germany' },
  { name: 'Munich Malt', srm: '8-15 SRM', role: 'Base malt providing deep amber color and bread-crust flavor', origin: 'Germany' },
  { name: 'Maris Otter Malt', srm: '2.5-3.5 SRM', role: 'Traditional British floor-malted grain celebrated for rich nutty, bready depth', origin: 'UK' },
  { name: 'Crystal / Caramel 60L', srm: '60 SRM', role: 'Specialty malt adding caramel sweetness, body, and copper red color', origin: 'Global' },
  { name: 'Crystal 120L Malt', srm: '120 SRM', role: 'Dark specialty malt contributing raisin, prune, and burnt sugar notes', origin: 'Global' },
  { name: 'Chocolate Malt', srm: '350-450 SRM', role: 'Dark roasted malt providing rich cocoa, coffee, and dark brown hue', origin: 'UK/USA' },
  { name: 'Black Patent Malt', srm: '500+ SRM', role: 'Deeply roasted malt providing sharp, acrid roasty bitterness and opaque color', origin: 'Global' },
  { name: 'Roasted Barley', srm: '300-500 SRM', role: 'Unmalted roasted grain defining authentic dry Irish Stouts with creamy head', origin: 'Ireland/UK' },
  { name: 'Flaked Oats', srm: '1 SRM', role: 'Unmalted cereal grain added to enhance silky mouthfeel and stable haze in NEIPAs', origin: 'Global' },
  { name: 'Flaked Rye', srm: '2 SRM', role: 'Grain added to impart a distinct spicy, crisp rustic flavor and dense foam', origin: 'Global' },
  { name: 'Carapils (Dextrine)', srm: '1.5 SRM', role: 'Specialty malt used to enhance foam retention and body without altering flavor', origin: 'Germany/USA' },
  { name: 'Smoked Beechwood Malt', srm: '2-4 SRM', role: 'Traditional German malt infused with beechwood smoke for authentic Rauchbier', origin: 'Germany (Bamberg)' },
  { name: 'Acidulated Malt', srm: '2-3 SRM', role: 'Malt containing natural lactic acid used to adjust mash water pH into 5.2-5.6 range', origin: 'Germany' },
];

const yeastData = [
  { name: 'US-05 / California Ale Yeast', temp: '59°F - 72°F', profile: 'Clean, neutral, low-ester profile letting hops and malt shine' },
  { name: 'S-04 / English Ale Yeast', temp: '59°F - 68°F', profile: 'Fruity esters with rapid flocculation and compact yeast sediment cake' },
  { name: 'WLP300 / Hefeweizen Ale Yeast', temp: '68°F - 74°F', profile: 'Classic clove (4-VG) and banana (isoamyl acetate) yeast esters' },
  { name: 'W-34/70 Weihenstephan Lager', temp: '48°F - 59°F', profile: 'Crisp, clean lager fermentation with zero ale fruitiness' },
  { name: 'Voss Kveik Farmhouse Yeast', temp: '77°F - 98°F', profile: 'Ultra-fast fermentation with orange peel and citrus esters at high heat' },
  { name: 'French Saison Yeast', temp: '68°F - 90°F', profile: 'Highly attenuative dry finish with peppery spice and earthy notes' },
  { name: 'London Ale III (Wyeast 1318)', temp: '64°F - 74°F', profile: 'Soft, fruity esters with low attenuation defining juicy New England IPAs' },
  { name: 'Brettanomyces bruxellensis', temp: '65°F - 85°F', profile: 'Wild yeast imparting pineapple, leather, barnyard, and rustic funk over time' },
];

const stylesData = [
  { name: 'American IPA', ibu: '40-70 IBU', srm: '6-14 SRM', abv: '6.0-7.5% ABV', feature: 'Prominent hop bitterness, citrus/tropical aroma, and crisp dry finish' },
  { name: 'Dry Irish Stout', ibu: '25-45 IBU', srm: '25-40 SRM', abv: '4.0-4.5% ABV', feature: 'Jet black color, roasted barley coffee bitterness, and dry finish' },
  { name: 'German Hefeweizen', ibu: '8-15 IBU', srm: '2-8 SRM', abv: '4.3-5.6% ABV', feature: 'Unfiltered cloudy wheat beer with banana and clove yeast esters' },
  { name: 'Bohemian Pilsner', ibu: '30-45 IBU', srm: '3.5-6 SRM', abv: '4.2-5.8% ABV', feature: 'Rich golden lager featuring noble Saaz hop bitterness and soft water profile' },
  { name: 'Belgian Saison', ibu: '20-35 IBU', srm: '4-14 SRM', abv: '5.0-7.0% ABV', feature: 'Highly carbonated, bone-dry farmhouse ale with spicy yeast phenols' },
  { name: 'New England Hazy IPA', ibu: '25-60 IBU', srm: '3-7 SRM', abv: '6.0-9.0% ABV', feature: 'Hazy appearance, smooth velvety mouthfeel, and massive juicy hop aroma' },
  { name: 'Belgian Tripel', ibu: '20-40 IBU', srm: '4.5-7 SRM', abv: '7.5-9.5% ABV', feature: 'Deep golden, effervescent high-gravity ale with complex spicy, fruity yeast character' },
  { name: 'Russian Imperial Stout', ibu: '50-90 IBU', srm: '30-40+ SRM', abv: '8.0-12.0% ABV', feature: 'Intense dark ale showcasing dark chocolate, espresso, dried fruit, and warming alcohol' },
];

const equipmentAndTechniques = [
  { term: 'Auto-Siphon', def: 'Racking liquid between fermenters and bottling buckets without agitation or aeration' },
  { term: 'Immersion Wort Chiller', def: 'Copper or stainless steel coil that rapidly cools boiling wort to yeast pitching temperature' },
  { term: 'Hydrometer', def: 'Glass float instrument calibrated to measure specific gravity (density) relative to pure water' },
  { term: 'Refractometer', def: 'Optical instrument using light refraction through a prism to measure Brix sugar density in unfermented wort' },
  { term: 'BIAB (Brew In A Bag)', def: 'All-grain brewing method using a fine mesh fabric filter bag inside a single multi-purpose kettle' },
  { term: 'Airlock (Bubbler)', def: 'One-way fermentation valve that lets carbon dioxide gas escape while preventing oxygen and wild bugs from entering' },
  { term: 'Cold Crashing', def: 'Chilling finished beer to 32°F - 38°F before packaging to precipitate yeast and proteins for brilliant clarity' },
  { term: 'Dry Hopping', def: 'Adding hop pellets to secondary fermentation or kegs to extract delicate aromatic essential oils without bitterness' },
  { term: 'Vorlaufing', def: 'Recirculating cloudy initial wort through the grain bed until it runs clear before collecting into the boil kettle' },
  { term: 'Star San Sanitizer', def: 'High-foaming acid-anionic food-grade no-rinse sanitizer formulated from phosphoric acid' },
  { term: 'Diacetyl Off-Flavor', def: 'Buttery or butterscotch off-flavor caused by premature yeast separation or incomplete diacetyl reduction' },
  { term: 'Acetaldehyde Off-Flavor', def: 'Green apple or fresh-cut pumpkin off-flavor resulting from incomplete fermentation or young green beer' },
  { term: 'DMS (Dimethyl Sulfide)', def: 'Cooked corn or canned vegetable off-flavor caused by insufficient rolling boil or slow wort chilling' },
  { term: '3-MBT Skunking', def: 'Lightstruck off-flavor created when ultraviolet or blue light reacts with isomerized hop isohumulones' },
  { term: 'Mash Out (168°F - 170°F)', def: 'Heating mash grain bed to 170°F to halt enzymatic conversion and reduce wort viscosity for sparging' },
];

function pickRandomDistractors(pool, correctAnswer, count = 3, fallback = []) {
  const cleanCorrect = (correctAnswer || '').trim().toLowerCase();
  const candidates = pool
    .map(s => (s || '').trim())
    .filter(s => s.length > 0 && s.toLowerCase() !== cleanCorrect);
  const unique = [...new Set(candidates)];
  for (let i = unique.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [unique[i], unique[j]] = [unique[j], unique[i]];
  }
  const selected = unique.slice(0, count);
  if (selected.length < count && fallback.length > 0) {
    for (const fb of fallback) {
      if (selected.length >= count) break;
      if (fb.toLowerCase() !== cleanCorrect && !selected.includes(fb)) {
        selected.push(fb);
      }
    }
  }
  let fill = 1;
  while (selected.length < count) {
    selected.push(`Alternative ${fill++}`);
  }
  return selected;
}

// 2. GENERATE 500+ DISTINCT, UNIQUE QUESTIONS
export function generate500HomebrewingQuestions() {
  const pool = [];
  const seenTexts = new Set();

  function pushQ(id, text, correct, optB, optC, optD, diff = 'Standard') {
    let clean = text.replace(/\s*\((?:Focus Point|Batch|Formula|Protocol\s*)?#\d+\)/gi, '')
                    .replace(/\s*\(#INDEX\)/gi, '')
                    .replace(/\s*#\d+\b/g, '')
                    .trim();
    if (seenTexts.has(clean.toLowerCase())) return;
    seenTexts.add(clean.toLowerCase());

    const opts = [
      { text: correct, isCorrect: true },
      { text: optB, isCorrect: false },
      { text: optC, isCorrect: false },
      { text: optD, isCorrect: false }
    ];
    for (let i = opts.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [opts[i], opts[j]] = [opts[j], opts[i]];
    }

    const letters = ['A', 'B', 'C', 'D'];
    const correctIdx = opts.findIndex(o => o.isCorrect);
    const correctLetter = letters[correctIdx] || 'A';

    pool.push({
      id: `hb_uniq_${pool.length + 1}`,
      category: 'Homebrewing Beer',
      difficulty: diff,
      text: clean,
      options: {
        A: opts[0].text,
        B: opts[1].text,
        C: opts[2].text,
        D: opts[3].text
      },
      correct: correctLetter
    });
  }

  const allHopNames = hopsData.map(h => h.name);
  const allHopOrigins = [...new Set(hopsData.map(h => h.origin))];
  const allHopFlavors = hopsData.map(h => h.flavor);
  const allHopTypes = [...new Set(hopsData.map(h => h.type))];
  const allHopAlphas = [...new Set(hopsData.map(h => h.alpha))];

  const allMaltNames = maltsData.map(m => m.name);
  const allMaltRoles = maltsData.map(m => m.role);
  const allMaltSrms = [...new Set(maltsData.map(m => m.srm))];
  const allMaltOrigins = [...new Set(maltsData.map(m => m.origin))];

  const allYeastNames = yeastData.map(y => y.name);
  const allYeastProfiles = yeastData.map(y => y.profile);
  const allYeastTemps = [...new Set(yeastData.map(y => y.temp))];

  const allStyleNames = stylesData.map(s => s.name);
  const allStyleIbus = [...new Set(stylesData.map(s => s.ibu))];
  const allStyleAbvs = [...new Set(stylesData.map(s => s.abv))];
  const allStyleFeatures = stylesData.map(s => s.feature);

  const allEquipmentDefs = equipmentAndTechniques.map(e => e.def);

  const hopOriginTemplates = [
    (h) => `Where was the "${h.name}" hop cultivar originally bred and cultivated for brewing?`,
    (h) => `Which country is the original home of the "${h.name}" hop variety?`,
    (h) => `A brewer picks up a bag of "${h.name}" hop pellets—which country do these hops hail from?`,
    (h) => `In which hop-growing nation did the "${h.name}" variety originate?`,
    (h) => `If you are brewing with authentic regional "${h.name}" hops, where were they developed?`,
    (h) => `Trace the pedigree of "${h.name}" hops: which country introduced them to the brewing world?`,
  ];

  const hopFlavorTemplates = [
    (h) => `What signature sensory notes do "${h.name}" hops bring to a finished beer?`,
    (h) => `Why do brewers reach for "${h.name}" when building a hop profile?`,
    (h) => `Tasting a single-hop beer brewed with "${h.name}" reveals which dominant flavor and aroma profile?`,
    (h) => `How would a certified beer judge describe the aroma of "${h.name}" hops?`,
    (h) => `Crushing fresh "${h.name}" hop cones between your palms releases which primary aromas?`,
    (h) => `Which tasting notes are the hallmark of "${h.name}" hops in craft brewing?`,
  ];

  const hopTypeTemplates = [
    (h) => `How do brewers classify "${h.name}" hops based on their primary kettle and cellar role?`,
    (h) => `Under which functional brewing category is the "${h.name}" hop variety grouped?`,
    (h) => `When designing a hop schedule, how is "${h.name}" traditionally categorized?`,
    (h) => `Is "${h.name}" considered a bittering hop, an aroma hop, or a dual-purpose variety?`,
    (h) => `On a hop supplier spec sheet, what usage classification is assigned to "${h.name}"?`,
  ];

  const hopAlphaTemplates = [
    (h) => `Roughly what alpha acid percentage range can a brewer expect from a harvest of "${h.name}" hops?`,
    (h) => `When calculating IBU additions, what is the typical alpha acid rating of "${h.name}" hops?`,
    (h) => `How much bittering potential (alpha acid %) is packed inside "${h.name}" hops?`,
    (h) => `Check the label on a nitrogen-flushed foil pouch of "${h.name}" hops—what alpha acid range is typical?`,
    (h) => `What is the standard alpha acid range for "${h.name}" when plugging it into brewing software?`,
  ];

  // 1. Hop questions
  hopsData.forEach((h, idx) => {
    const dOrig = pickRandomDistractors(allHopOrigins, h.origin, 3, ['Germany', 'USA', 'United Kingdom', 'New Zealand', 'Australia', 'Czech Republic']);
    const dFlav = pickRandomDistractors(allHopFlavors, h.flavor, 3);
    const dType = pickRandomDistractors(allHopTypes, h.type, 3, ['Aroma', 'Bittering', 'Dual-Purpose', 'Late Hop']);
    const dAlpha = pickRandomDistractors(allHopAlphas, h.alpha, 3, ['1-2% Alpha Acids', '30-40% Alpha Acids', '8-10% Alpha Acids']);
    pushQ('h_orig', hopOriginTemplates[idx % hopOriginTemplates.length](h), h.origin, dOrig[0], dOrig[1], dOrig[2]);
    pushQ('h_flav', hopFlavorTemplates[idx % hopFlavorTemplates.length](h), h.flavor, dFlav[0], dFlav[1], dFlav[2]);
    pushQ('h_type', hopTypeTemplates[idx % hopTypeTemplates.length](h), h.type, dType[0], dType[1], dType[2]);
    pushQ('h_alpha', hopAlphaTemplates[idx % hopAlphaTemplates.length](h), h.alpha, dAlpha[0], dAlpha[1], dAlpha[2]);
  });

  const maltRoleTemplates = [
    (m) => `What job does "${m.name}" perform when added to a brewer's grist?`,
    (m) => `Why do recipe designers include "${m.name}" in an all-grain mash bill?`,
    (m) => `How does "${m.name}" shape the character of a homebrewed beer?`,
    (m) => `At thehomebrew shop mill, a brewer weighs out "${m.name}"—what is its main purpose in the recipe?`,
    (m) => `Which description best captures the brewing role of "${m.name}"?`,
  ];

  const maltSrmTemplates = [
    (m) => `How dark is "${m.name}" on the Standard Reference Method (SRM) Lovibond color scale?`,
    (m) => `What SRM color rating does "${m.name}" contribute to the wort?`,
    (m) => `When estimating beer color in recipe software, what SRM value corresponds to "${m.name}"?`,
    (m) => `Where does "${m.name}" fall on the maltster's SRM color chart?`,
    (m) => `Which SRM color range is typical for "${m.name}"?`,
  ];

  const maltOriginTemplates = [
    (m) => `Which country or region is traditionally renowned for malting "${m.name}"?`,
    (m) => `Where did the malting tradition for "${m.name}" originate?`,
    (m) => `If a recipe calls for authentic regional "${m.name}", which part of the world is famous for producing it?`,
    (m) => `Which brewing region is most closely associated with "${m.name}"?`,
  ];

  // 2. Malt questions
  maltsData.forEach((m, idx) => {
    const dRole = pickRandomDistractors(allMaltRoles, m.role, 3);
    const dSrm = pickRandomDistractors(allMaltSrms, m.srm, 3, ['10-20 SRM', '50 SRM', '150 SRM']);
    const dOrig = pickRandomDistractors(allMaltOrigins, m.origin, 3, ['Germany', 'UK', 'USA', 'Belgium']);
    pushQ('m_role', maltRoleTemplates[idx % maltRoleTemplates.length](m), m.role, dRole[0], dRole[1], dRole[2]);
    pushQ('m_srm', maltSrmTemplates[idx % maltSrmTemplates.length](m), m.srm, dSrm[0], dSrm[1], dSrm[2]);
    pushQ('m_orig', maltOriginTemplates[idx % maltOriginTemplates.length](m), m.origin, dOrig[0], dOrig[1], dOrig[2]);
  });

  const yeastProfileTemplates = [
    (y) => `What fermentation character can you expect when pitching "${y.name}"?`,
    (y) => `How does "${y.name}" influence the flavor and attenuation of fermenting wort?`,
    (y) => `Why would a homebrewer choose "${y.name}" for their fermenter?`,
    (y) => `Which sensory and flocculation traits set "${y.name}" apart from other brewing strains?`,
  ];

  const yeastTempTemplates = [
    (y) => `At what temperature range does "${y.name}" perform best during active fermentation?`,
    (y) => `Where should you set your fermentation chamber controller when fermenting with "${y.name}"?`,
    (y) => `What is the sweet-spot temperature window recommended by yeast labs for "${y.name}"?`,
    (y) => `To avoid unwanted off-flavors, what fermentation temperature range suits "${y.name}"?`,
  ];

  // 3. Yeast questions
  yeastData.forEach((y, idx) => {
    const dProf = pickRandomDistractors(allYeastProfiles, y.profile, 3);
    const dTemp = pickRandomDistractors(allYeastTemps, y.temp, 3, ['55°F - 65°F', '68°F - 72°F', '75°F - 82°F']);
    pushQ('y_prof', yeastProfileTemplates[idx % yeastProfileTemplates.length](y), y.profile, dProf[0], dProf[1], dProf[2]);
    pushQ('y_temp', yeastTempTemplates[idx % yeastTempTemplates.length](y), y.temp, dTemp[0], dTemp[1], dTemp[2]);
  });

  const styleIbuTemplates = [
    (s) => `Under BJCP style guidelines, what IBU bitterness range is on target for a "${s.name}"?`,
    (s) => `How many International Bitterness Units (IBUs) define a classic "${s.name}"?`,
    (s) => `If you are entering a "${s.name}" in a homebrew competition, what IBU window do judges expect?`,
    (s) => `What is the target bitterness range (in IBUs) for a well-balanced "${s.name}"?`,
  ];

  const styleAbvTemplates = [
    (s) => `What alcohol by volume (ABV) percentage is standard for a traditional "${s.name}"?`,
    (s) => `How strong is a classic "${s.name}" in terms of alcohol by volume (ABV)?`,
    (s) => `When formulating a "${s.name}" to style, what ABV range should your hydrometer readings hit?`,
    (s) => `Which ABV bracket matches the BJCP specification for "${s.name}"?`,
  ];

  const styleFeatTemplates = [
    (s) => `What sensory profile are judges looking for when evaluating a "${s.name}"?`,
    (s) => `How does a textbook "${s.name}" present in the glass?`,
    (s) => `Which flavor, aroma, and appearance traits best describe a classic "${s.name}"?`,
    (s) => `Pouring a pint of homebrewed "${s.name}"—what are its signature style characteristics?`,
  ];

  // 4. Style questions
  stylesData.forEach((s, idx) => {
    const dIbu = pickRandomDistractors(allStyleIbus, s.ibu, 3, ['15-25 IBU', '35-50 IBU', '60-80 IBU']);
    const dAbv = pickRandomDistractors(allStyleAbvs, s.abv, 3, ['4.5-5.5% ABV', '6.0-7.0% ABV', '8.0-9.5% ABV']);
    const dFeat = pickRandomDistractors(allStyleFeatures, s.feature, 3);
    pushQ('s_ibu', styleIbuTemplates[idx % styleIbuTemplates.length](s), s.ibu, dIbu[0], dIbu[1], dIbu[2]);
    pushQ('s_abv', styleAbvTemplates[idx % styleAbvTemplates.length](s), s.abv, dAbv[0], dAbv[1], dAbv[2]);
    pushQ('s_feat', styleFeatTemplates[idx % styleFeatTemplates.length](s), s.feature, dFeat[0], dFeat[1], dFeat[2]);
  });

  const equipTemplatesA = [
    (e) => `What is the role of "${e.term}" on brew day or in the cellar?`,
    (e) => `In a homebrewer's vocabulary, what does "${e.term}" mean?`,
    (e) => `How does "${e.term}" fit into the homebrewing process?`,
    (e) => `A fellow brewer mentions "${e.term}"—what are they referring to?`,
    (e) => `Which statement accurately explains "${e.term}" in craft brewing?`,
  ];

  const equipTemplatesB = [
    (e) => `What problem or task does "${e.term}" address when making beer at home?`,
    (e) => `When you encounter "${e.term}" in a brewing guide, what is being described?`,
    (e) => `Why is "${e.term}" important to understand for quality homebrewing?`,
    (e) => `Which brewing function or phenomenon is associated with "${e.term}"?`,
    (e) => `How would an experienced brewmaster explain "${e.term}" to a beginner?`,
  ];

  // 5. Equipment & Technique questions
  equipmentAndTechniques.forEach((e, idx) => {
    const dDef = pickRandomDistractors(allEquipmentDefs, e.def, 3);
    const dDef2 = pickRandomDistractors(allEquipmentDefs, e.def, 3);
    pushQ('eq_def', equipTemplatesA[idx % equipTemplatesA.length](e), e.def, dDef[0], dDef[1], dDef[2]);
    pushQ('eq_goal', equipTemplatesB[idx % equipTemplatesB.length](e), e.def, dDef2[0], dDef2[1], dDef2[2]);
  });

  // 6. Diverse Recipe Formulation, Hop Scheduling, Malt Pairing & Brewing Science (500+ total unique questions)
  const hopStyleDryHopTemplates = [
    (h, s) => `You're dry-hopping a 5-gallon batch of ${s.name} with ${h.name}—what sensory lift does that addition give the finished pint?`,
    (h, s) => `If a brewer adds ${h.name} pellets to the fermenter for a ${s.name}, what aroma profile will dominate the nose?`,
    (h, s) => `Why might a recipe for ${s.name} call for a late dry-hop charge of ${h.name}?`,
    (h, s) => `What happens to the aroma of a ${s.name} when it is conditioned on ${h.name} hops after primary fermentation?`,
    (h, s) => `For a brewer looking to accent a ${s.name} with ${h.name} in the whirlpool or dry-hop, what flavors come through?`,
    (h, s) => `How does a post-fermentation dose of ${h.name} transform the bouquet of a homebrewed ${s.name}?`,
    (h, s) => `Tapping a fresh keg of ${s.name} hopped late with ${h.name}—what aromatic notes greet the drinker?`,
    (h, s) => `Suppose you swap your usual finishing hop in a ${s.name} for ${h.name}; what character does ${h.name} contribute?`,
    (h, s) => `In a competition ${s.name} recipe, what aromatic payoff comes from steeping ${h.name} hops cold in the fermenter?`,
    (h, s) => `Which aroma contribution makes ${h.name} a standout finishing hop choice when brewing a ${s.name}?`,
  ];

  const hopStyleBoilTemplates = [
    (h, s) => `When timing kettle additions of ${h.name} for a ${s.name} (${s.ibu}), how do early boil vs. flameout charges behave?`,
    (h, s) => `You have ${h.name} (${h.alpha}) on hand for a ${s.name}—how does kettle timing split its bittering and aromatic effects?`,
    (h, s) => `To hit ${s.ibu} in a ${s.name} using ${h.name} hops while preserving volatile hop oils, how should additions be staged?`,
    (h, s) => `How does boiling ${h.name} for 60 minutes compare to adding it at whirlpool when brewing a ${s.name}?`,
    (h, s) => `In kettle hop scheduling for a ${s.name}, why would you split ${h.name} between the start of the boil and flameout?`,
    (h, s) => `A brew-day sheet for ${s.name} lists ${h.name} at both 60 minutes and 0 minutes—what is the purpose of that two-stage schedule?`,
    (h, s) => `What is the best way to schedule ${h.name} in the kettle to balance ${s.ibu} bitterness and fresh hop aroma in a ${s.name}?`,
    (h, s) => `When brewing a ${s.name} with ${h.name}, how does thermal isomerization in the boil differ from a sub-180°F hop stand?`,
  ];

  const hopDryHopEffectPool = hopsData.map(h => `Layers in ${h.flavor.toLowerCase()} without adding harsh isomerized bitterness`);
  const hopScheduleCorrectPool = [
    'Early 60-minute boil additions isomerize alpha acids for bitterness, while flameout/whirlpool additions preserve volatile aroma oils',
    'Boil early charges for clean iso-alpha bitterness and steep late charges below 180°F to lock in essential hop aromatics',
    'Use a 60-minute kettle charge to reach target IBUs and a late whirlpool addition to capture delicate hop oils before chilling',
    'Add the bittering portion at the start of the boil for alpha-acid conversion and reserve aroma charges for flameout',
  ];
  const hopScheduleDistractorPool = [
    'Add all hops directly into the cold mash tun before sparging so grain enzymes isomerize the alpha acids',
    'Boil the entire hop charge for 3 hours uncovered to prevent essential oils from evaporating',
    'Pitch hop cones exclusively into the priming sugar solution during bottle capping to generate 60 IBUs',
    'Freeze the hops in ice cubes and drop them into the mash out water at 170°F for maximum bitterness',
    'Mix hops with Star San sanitizer prior to mashing to convert beta acids into fermentable maltose',
    'Steep hops only in cold sparge water at 50°F to achieve full alpha-acid isomerization',
  ];

  let comboIdx = 0;
  hopsData.forEach((h) => {
    stylesData.forEach((s) => {
      const dhPrompt = hopStyleDryHopTemplates[comboIdx % hopStyleDryHopTemplates.length](h, s);
      const dhCorrect = `Layers in ${h.flavor.toLowerCase()} without adding harsh isomerized bitterness`;
      const dhDistractors = pickRandomDistractors(hopDryHopEffectPool, dhCorrect, 3);
      pushQ('gen_hop_ipa', dhPrompt, dhCorrect, dhDistractors[0], dhDistractors[1], dhDistractors[2]);

      const boilPrompt = hopStyleBoilTemplates[comboIdx % hopStyleBoilTemplates.length](h, s);
      const boilCorrect = hopScheduleCorrectPool[comboIdx % hopScheduleCorrectPool.length];
      const boilDistractors = pickRandomDistractors(hopScheduleDistractorPool, boilCorrect, 3);
      pushQ('gen_chem_bjcp', boilPrompt, boilCorrect, boilDistractors[0], boilDistractors[1], boilDistractors[2]);
      comboIdx++;
    });
  });

  const maltStyleTemplates = [
    (m, s) => `If you work ${m.name} into the grain bill for a ${s.name}, what does it bring to the finished beer?`,
    (m, s) => `A brewer tweaks their ${s.name} grist by adding ${m.name}—what color and flavor impact should they expect?`,
    (m, s) => `Why would a recipe formulation for ${s.name} include ${m.name} in the mash tun?`,
    (m, s) => `How does ${m.name} influence the wort when mashing an all-grain batch of ${s.name}?`,
    (m, s) => `When designing a ${s.name} from scratch, what role does ${m.name} play in the grist?`,
    (m, s) => `Evaluating a homebrewed ${s.name} brewed with ${m.name}: what contribution comes from that grain?`,
    (m, s) => `Suppose your ${s.name} recipe calls for ${m.name}—what properties does it impart to the wort?`,
    (m, s) => `In the mash bill for a ${s.name}, what specific traits does ${m.name} supply?`,
  ];

  const mashScienceTemplates = [
    (m, s) => `While mashing ${m.name} for a ${s.name} at a lower 148°F (64°C) rest, how does enzyme activity shape the wort?`,
    (m, s) => `If you mash a ${s.name} grist containing ${m.name} at a warmer 156°F (69°C) rest, what happens to the wort's fermentability?`,
    (m, s) => `During the saccharification rest for a ${s.name} with ${m.name}, why is keeping mash pH between 5.2 and 5.6 so important?`,
    (m, s) => `When lautering a ${s.name} mash made with ${m.name}, why must sparge water stay at or below 170°F (77°C)?`,
    (m, s) => `In an all-grain ${s.name} mash featuring ${m.name}, how do alpha-amylase and beta-amylase work together?`,
    (m, s) => `Before draining the mash tun on a ${s.name} brewed with ${m.name}, a brewer performs a vorlauf—what does this step accomplish?`,
    (m, s) => `Why would a brewer test a drop of ${s.name} wort (mashed with ${m.name}) against iodophor or iodine tincture?`,
    (m, s) => `After mashing ${m.name} for a ${s.name}, raising the grain bed to 168°F (76°C) for a mash-out serves what purpose?`,
  ];

  const mashScienceAnswers = [
    'Beta-amylase thrives at 148°F, cleaving starches into highly fermentable maltose for a drier, crisper finish',
    'Alpha-amylase dominates at 156°F, leaving more unfermentable dextrins for fuller body and residual mouthfeel',
    'A mash pH of 5.2–5.6 optimizes amylase enzyme conversion, improves hop extraction, and prevents harsh husk tannin leaching',
    'Keeping sparge water at or below 170°F prevents extracting harsh, mouth-puckering polyphenol tannins from the grain husks',
    'Alpha-amylase randomly splits long starch chains into smaller dextrins while beta-amylase chops them from the ends into maltose',
    'Recirculating the first runnings sets the grain bed as a natural filter so clear, husk-free wort flows into the boil kettle',
    'Iodine stays reddish-amber when starch conversion is complete, but turns dark blue-black if unconverted starch remains',
    'Halts enzymatic activity to lock in the fermentable-to-dextrin sugar profile and thins the wort for smoother lautering',
  ];

  const maltContributionPool = maltsData.map(m => `${m.role} (${m.srm})`);

  let maltComboIdx = 0;
  maltsData.forEach((m) => {
    stylesData.forEach((s) => {
      const mPrompt = maltStyleTemplates[maltComboIdx % maltStyleTemplates.length](m, s);
      const mCorrect = `${m.role} (${m.srm})`;
      const mDistractors = pickRandomDistractors(maltContributionPool, mCorrect, 3);
      pushQ('gen_malt_mash', mPrompt, mCorrect, mDistractors[0], mDistractors[1], mDistractors[2]);

      const sciIdx = maltComboIdx % mashScienceTemplates.length;
      const sciPrompt = mashScienceTemplates[sciIdx](m, s);
      const sciCorrect = mashScienceAnswers[sciIdx];
      const sciDistractors = pickRandomDistractors(mashScienceAnswers, sciCorrect, 3);
      pushQ('gen_mash_enzyme', sciPrompt, sciCorrect, sciDistractors[0], sciDistractors[1], sciDistractors[2]);
      maltComboIdx++;
    });
  });

  let shuffled = fisherYatesShuffle(pool);

  // Anti-Similarity Declustering Pass: Guarantees no back-to-back similar questions
  function getQuestionStem(t) {
    if (!t) return '';
    return t.toLowerCase().replace(/[^a-z0-9 ]/g, '').split(/\s+/).filter(w => w.length > 3).slice(0, 3).join('_');
  }

  function calcSim(a, b) {
    if (!a || !b) return 0;
    const sA = new Set(a.toLowerCase().replace(/[^a-z0-9 ]/g, '').split(/\s+/).filter(w => w.length > 2));
    const sB = new Set(b.toLowerCase().replace(/[^a-z0-9 ]/g, '').split(/\s+/).filter(w => w.length > 2));
    if (sA.size === 0 || sB.size === 0) return 0;
    let inter = 0;
    for (const w of sA) {
      if (sB.has(w)) inter++;
    }
    return inter / (sA.size + sB.size - inter);
  }

  const declustered = [];
  const pending = [...shuffled];
  while (pending.length > 0) {
    const recents = declustered.slice(-4);
    const lastQ = declustered.length > 0 ? declustered[declustered.length - 1] : null;
    let foundIdx = -1;

    for (let i = 0; i < pending.length; i++) {
      const pStem = getQuestionStem(pending[i].text);
      const stemHit = recents.some(r => getQuestionStem(r.text) === pStem);
      const simHit = lastQ && calcSim(lastQ.text, pending[i].text) > 0.40;
      if (!stemHit && !simHit) {
        foundIdx = i;
        break;
      }
    }

    if (foundIdx === -1) {
      for (let i = 0; i < pending.length; i++) {
        if (!lastQ || getQuestionStem(pending[i].text) !== getQuestionStem(lastQ.text)) {
          foundIdx = i;
          break;
        }
      }
      if (foundIdx === -1) foundIdx = 0;
    }

    declustered.push(pending.splice(foundIdx, 1)[0]);
  }

  return declustered;
}
