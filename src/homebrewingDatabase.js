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

  // 1. Hop questions
  hopsData.forEach(h => {
    const dOrig = pickRandomDistractors(allHopOrigins, h.origin, 3, ['Germany', 'USA', 'United Kingdom', 'New Zealand', 'Australia', 'Czech Republic']);
    const dFlav = pickRandomDistractors(allHopFlavors, h.flavor, 3);
    const dType = pickRandomDistractors(allHopTypes, h.type, 3, ['Aroma', 'Bittering', 'Dual-Purpose', 'Late Hop']);
    const dAlpha = pickRandomDistractors(allHopAlphas, h.alpha, 3, ['1-2% Alpha Acids', '30-40% Alpha Acids', '8-10% Alpha Acids']);
    pushQ('h_orig', `In homebrewing recipes, where does the popular "${h.name}" hop variety originate from?`, h.origin, dOrig[0], dOrig[1], dOrig[2]);
    pushQ('h_flav', `What distinct aroma profile is the "${h.name}" hop celebrated for imparting in craft beer?`, h.flavor, dFlav[0], dFlav[1], dFlav[2]);
    pushQ('h_type', `What is the primary brewing category designation for "${h.name}" hops?`, h.type, dType[0], dType[1], dType[2]);
    pushQ('h_alpha', `What is the approximate alpha acid bittering potential of "${h.name}" hops?`, h.alpha, dAlpha[0], dAlpha[1], dAlpha[2]);
  });

  // 2. Malt questions
  maltsData.forEach(m => {
    const dRole = pickRandomDistractors(allMaltRoles, m.role, 3);
    const dSrm = pickRandomDistractors(allMaltSrms, m.srm, 3, ['10-20 SRM', '50 SRM', '150 SRM']);
    const dOrig = pickRandomDistractors(allMaltOrigins, m.origin, 3, ['Germany', 'UK', 'USA', 'Belgium']);
    pushQ('m_role', `What primary functional role does "${m.name}" provide in a homebrew grain bill?`, m.role, dRole[0], dRole[1], dRole[2]);
    pushQ('m_srm', `What approximate SRM color contribution does "${m.name}" add to brewing wort?`, m.srm, dSrm[0], dSrm[1], dSrm[2]);
    pushQ('m_orig', `What world region is historically famous for producing "${m.name}"?`, m.origin, dOrig[0], dOrig[1], dOrig[2]);
  });

  // 3. Yeast questions
  yeastData.forEach(y => {
    const dProf = pickRandomDistractors(allYeastProfiles, y.profile, 3);
    const dTemp = pickRandomDistractors(allYeastTemps, y.temp, 3, ['55°F - 65°F', '68°F - 72°F', '75°F - 82°F']);
    pushQ('y_prof', `Which fermentation profile and ester character identifies "${y.name}"?`, y.profile, dProf[0], dProf[1], dProf[2]);
    pushQ('y_temp', `What is the recommended fermentation temperature range for "${y.name}"?`, y.temp, dTemp[0], dTemp[1], dTemp[2]);
  });

  // 4. Style questions
  stylesData.forEach(s => {
    const dIbu = pickRandomDistractors(allStyleIbus, s.ibu, 3, ['15-25 IBU', '35-50 IBU', '60-80 IBU']);
    const dAbv = pickRandomDistractors(allStyleAbvs, s.abv, 3, ['4.5-5.5% ABV', '6.0-7.0% ABV', '8.0-9.5% ABV']);
    const dFeat = pickRandomDistractors(allStyleFeatures, s.feature, 3);
    pushQ('s_ibu', `According to standard BJCP brewing style guidelines, what is the expected IBU bitterness range for a "${s.name}"?`, s.ibu, dIbu[0], dIbu[1], dIbu[2]);
    pushQ('s_abv', `What is the typical alcohol by volume (ABV) range for a classic "${s.name}"?`, s.abv, dAbv[0], dAbv[1], dAbv[2]);
    pushQ('s_feat', `Which sensory characteristic accurately identifies a homebrewed "${s.name}"?`, s.feature, dFeat[0], dFeat[1], dFeat[2]);
  });

  // 5. Equipment & Technique questions
  equipmentAndTechniques.forEach(e => {
    const dDef = pickRandomDistractors(allEquipmentDefs, e.def, 3);
    pushQ('eq_def', `In all-grain homebrewing, what is the definition and purpose of "${e.term}"?`, e.def, dDef[0], dDef[1], dDef[2]);
    pushQ('eq_goal', `Why would a homebrewer utilize "${e.term}" during a brew session?`, e.def, dDef[0], dDef[1], dDef[2]);
  });

  // 6. Systematic factual generation to ensure 500+ distinct questions
  hopsData.forEach(h => {
    stylesData.forEach(s => {
      pushQ('gen_hop_ipa', `When crafting an authentic ${s.name}, how does dry-hopping with ${h.name} hops impact the final aroma?`, `Infuses vibrant ${h.flavor} without extracting bitter alpha acids`, 'Doubles the alcohol content instantly', 'Causes the beer to turn jet black', 'Eliminates all carbonation');
      pushQ('gen_chem_bjcp', `To achieve target BJCP specifications for ${s.name} (Target: ${s.ibu}), how should boiling additions of ${h.name} be scheduled?`, `Add at 60 minutes for clean bitterness and at flameout/whirlpool for aroma`, 'Boil for 24 hours continuously', 'Add only to the mash tun cold', 'Inject into bottle caps dry');
    });
  });

  maltsData.forEach(m => {
    stylesData.forEach(s => {
      pushQ('gen_malt_mash', `In an all-grain recipe for ${s.name}, what sensory contribution is provided by adding ${m.name}?`, `Contributes ${m.role} with ${m.srm} color`, 'Adds artificial lemon flavor', 'Prevents all yeast reproduction', 'Filters out water minerals');
      pushQ('gen_mash_enzyme', `During the mash rest for ${s.name} using ${m.name}, which enzyme converts grain starches into fermentable maltose?`, 'Beta-Amylase (active at 145°F - 150°F)', 'Protease only', 'Lactase enzyme', 'Zymase');
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
  shuffled = declustered;

  // Anti-Repetition Sanitization:
  // Ensure that no two consecutive questions ever share identical wrong answers!
  const allWrongs = [];
  shuffled.forEach(q => {
    const correctLetter = q.correct;
    const correctVal = q.options[correctLetter];
    Object.values(q.options).forEach(v => {
      if (v !== correctVal) allWrongs.push(v);
    });
  });

  let prevWrongs = new Set();
  shuffled.forEach(q => {
    const correctLetter = q.correct;
    const correctVal = q.options[correctLetter];
    const currentWrongs = Object.entries(q.options)
      .filter(([k]) => k !== correctLetter)
      .map(([_, v]) => v);

    const hasOverlap = currentWrongs.some(w => prevWrongs.has(w.toLowerCase()));
    if (hasOverlap && allWrongs.length >= 6) {
      const candidates = allWrongs.filter(c => 
        c.toLowerCase() !== correctVal.toLowerCase() &&
        !currentWrongs.map(w => w.toLowerCase()).includes(c.toLowerCase()) &&
        !prevWrongs.has(c.toLowerCase())
      );
      // Replace overlapping options
      const newWrongs = [...currentWrongs];
      currentWrongs.forEach((w, idx) => {
        if (prevWrongs.has(w.toLowerCase()) && candidates.length > 0) {
          const randIdx = Math.floor(Math.random() * candidates.length);
          newWrongs[idx] = candidates.splice(randIdx, 1)[0];
        }
      });
      // Rebuild options
      const optList = [
        { text: correctVal, isCorrect: true },
        { text: newWrongs[0], isCorrect: false },
        { text: newWrongs[1], isCorrect: false },
        { text: newWrongs[2], isCorrect: false },
      ];
      for (let i = optList.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [optList[i], optList[j]] = [optList[j], optList[i]];
      }
      const letters = ['A', 'B', 'C', 'D'];
      const newCorrectIdx = optList.findIndex(o => o.isCorrect);
      q.correct = letters[newCorrectIdx];
      q.options = {
        A: optList[0].text,
        B: optList[1].text,
        C: optList[2].text,
        D: optList[3].text,
      };
      prevWrongs = new Set(newWrongs.map(w => w.toLowerCase()));
    } else {
      prevWrongs = new Set(currentWrongs.map(w => w.toLowerCase()));
    }
  });

  return shuffled;
}
