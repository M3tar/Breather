const path = require("node:path");
const sharp = require("sharp");

const repositoryRoot = path.resolve(__dirname, "../../..");
const sourceRoot = __dirname;
const outputRoot = path.resolve(__dirname, "..");

const backgroundPath = path.join(
  repositoryRoot,
  "Sources/Breather/Resources/Backgrounds/rest-background-moon.png",
);
const iconPath = path.join(
  repositoryRoot,
  "Sources/Breather/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png",
);
const variants = [
  {
    language: "en",
    layout: "hero-hybrid-layout.svg",
    output: "hero-hybrid.png",
    focus: "screenshots/timer-popover-running-jade.en.png",
    mirroring: "screenshots/timer-popover-mirroring-light.en.png",
  },
  {
    language: "zh-CN",
    layout: "hero-hybrid-layout-zh-cn.svg",
    output: "hero-hybrid-zh-cn.png",
    focus: "screenshots/timer-popover-running-jade.jpg",
    mirroring: "screenshots/timer-popover-mirroring-dark.jpg",
  },
];

const roundedMask = (width, height, radius) => Buffer.from(
  `<svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg"><rect width="${width}" height="${height}" rx="${radius}" fill="#fff"/></svg>`,
);

async function roundedImage(input, width, radius) {
  const resized = await sharp(input)
    .resize({ width })
    .png()
    .toBuffer({ resolveWithObject: true });

  return sharp(resized.data)
    .composite([{ input: roundedMask(resized.info.width, resized.info.height, radius), blend: "dest-in" }])
    .png()
    .toBuffer();
}

async function render({ layout: layoutName, output: outputName, focus: focusImage, mirroring: mirroringImage }) {
  const background = await sharp(backgroundPath)
    .extract({ left: 100, top: 180, width: 1440, height: 648 })
    .resize(1200, 540)
    .png()
    .toBuffer();
  const layout = await sharp(path.join(sourceRoot, layoutName)).png().toBuffer();
  const icon = await roundedImage(iconPath, 70, 18);
  const focus = await roundedImage(path.join(repositoryRoot, focusImage), 280, 24);
  const mirroring = await roundedImage(path.join(repositoryRoot, mirroringImage), 205, 22);

  const composition = await sharp({
    create: {
      width: 1200,
      height: 540,
      channels: 4,
      background: { r: 9, g: 13, b: 32, alpha: 1 },
    },
  })
    .composite([
      { input: background, left: 0, top: 0 },
      { input: layout, left: 0, top: 0 },
      { input: icon, left: 50, top: 36 },
      { input: focus, left: 775, top: 95 },
      { input: mirroring, left: 958, top: 180 },
    ])
    .png()
    .toBuffer();

  await sharp(composition)
    .composite([{ input: roundedMask(1200, 540, 32), blend: "dest-in" }])
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toFile(path.join(outputRoot, outputName));
}

const language = process.argv[2] || "all";
const selectedVariants = variants.filter((variant) => language === "all" || variant.language === language);
if (selectedVariants.length === 0) {
  throw new Error("Usage: node render-hybrid-hero.cjs [en|zh-CN|all]");
}

Promise.all(selectedVariants.map(render))
  .then(() => {
    console.log(`Rendered hybrid heroes: ${selectedVariants.map((variant) => variant.language).join(", ")}.`);
  })
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
