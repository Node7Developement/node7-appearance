Node7AppearanceConfig = {}

Node7AppearanceConfig.Debug = false
Node7AppearanceConfig.AutoCreateTables = true
Node7AppearanceConfig.NotifyTitle = 'NODE7 Appearance'

Node7AppearanceConfig.OpenControls = {
    0xCEFD9220, -- INPUT_CONTEXT / E
    0xD9D0E1C0  -- fallback Enter-style hash used by some RedM resources
}

Node7AppearanceConfig.DefaultSkin = {
    sex = 1,
    model = 'mp_male',
    head = 1,
    skin_tone = 1,
    body_size = 1,
    body_waist = 11,
    chest_size = 6,
    height = 100
}

Node7AppearanceConfig.Shops = {
    { label = 'Valentine Tailor', coords = { x = -325.95, y = 806.58, z = 117.89 }, radius = 2.0 },
    { label = 'Rhodes Tailor', coords = { x = 1322.99, y = -1291.02, z = 77.03 }, radius = 2.0 },
    { label = 'Saint Denis Tailor', coords = { x = 2554.99, y = -1168.60, z = 53.68 }, radius = 2.0 },
    { label = 'Blackwater Tailor', coords = { x = -762.00, y = -1291.98, z = 43.85 }, radius = 2.0 },
    { label = 'Strawberry Tailor', coords = { x = -1792.50, y = -392.38, z = 160.35 }, radius = 2.0 },
    { label = 'Armadillo Tailor', coords = { x = -3687.79, y = -2630.85, z = -13.40 }, radius = 2.0 },
    { label = 'Tumbleweed Tailor', coords = { x = -5480.85, y = -2934.57, z = -0.38 }, radius = 2.0 }
}

Node7AppearanceConfig.Wardrobes = {
    { label = 'Valentine Wardrobe', coords = { x = -325.29, y = 766.24, z = 117.48 }, radius = 2.0 },
    { label = 'Strawberry Wardrobe', coords = { x = -1817.11, y = -368.77, z = 166.54 }, radius = 2.0 },
    { label = 'Blackwater Wardrobe', coords = { x = -825.40, y = -1323.76, z = 47.91 }, radius = 2.0 },
    { label = 'Rhodes Wardrobe', coords = { x = 1331.86, y = -1377.35, z = 80.55 }, radius = 2.0 },
    { label = 'Saint Denis Wardrobe', coords = { x = 2550.67, y = -1159.46, z = 53.73 }, radius = 2.0 }
}

Node7AppearanceConfig.ClothingCategories = {
    'hats',
    'masks',
    'neckwear',
    'shirts_full',
    'vests',
    'coats',
    'coats_closed',
    'ponchos',
    'cloaks',
    'gloves',
    'pants',
    'skirts',
    'chaps',
    'boots',
    'spats',
    'boot_accessories',
    'belts',
    'buckles',
    'gunbelts',
    'holsters_left',
    'belts_holsters',
    'accessories',
    'jewelry_rings_left',
    'jewelry_rings_right',
    'satchels',
    'loadouts'
}

Node7AppearanceConfig.HairCategories = {
    'hair',
    'beard'
}

Node7AppearanceConfig.FeatureGroups = {
    body = {
        'body_size',
        'body_waist',
        'chest_size',
        'height',
        'head',
        'skin_tone'
    },
    face = {
        'face_width',
        'face_depth',
        'forehead_size',
        'eyebrow_height',
        'eyebrow_width',
        'eyebrow_depth',
        'eyes_depth',
        'eyes_angle',
        'eyes_distance',
        'eyes_height',
        'nose_width',
        'nose_size',
        'nose_height',
        'nose_angle',
        'nose_curvature',
        'nostrils_distance',
        'mouth_width',
        'mouth_depth',
        'mouth_y_pos',
        'mouth_x_pos',
        'upper_lip_height',
        'upper_lip_width',
        'upper_lip_depth',
        'lower_lip_height',
        'lower_lip_width',
        'jaw_height',
        'jaw_width',
        'jaw_depth',
        'chin_height',
        'chin_width',
        'chin_depth',
        'cheekbones_height',
        'cheekbones_width',
        'cheekbones_depth',
        'ears_width',
        'ears_angle',
        'ears_height',
        'ears_size'
    }
}

Node7AppearanceConfig.Labels = {
    hats = 'Hats', masks = 'Masks', neckwear = 'Neckwear', shirts_full = 'Shirts', vests = 'Vests',
    coats = 'Coats', coats_closed = 'Closed Coats', ponchos = 'Ponchos', cloaks = 'Cloaks', gloves = 'Gloves',
    pants = 'Pants', skirts = 'Skirts', chaps = 'Chaps', boots = 'Boots', spats = 'Spats',
    boot_accessories = 'Boot Accessories', belts = 'Belts', buckles = 'Buckles', gunbelts = 'Gunbelts',
    holsters_left = 'Holsters', belts_holsters = 'Belt Holsters', accessories = 'Accessories',
    jewelry_rings_left = 'Left Rings', jewelry_rings_right = 'Right Rings', satchels = 'Satchels', loadouts = 'Loadouts',
    hair = 'Hair', beard = 'Beard'
}
