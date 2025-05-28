const puppeteer = require("puppeteer");
const yargs = require("yargs");
const fs = require("fs");

(async () => {
  const argv = yargs
    .option("url", {
      alias: "u",
      description: "The URL of the page to print",
      type: "string",
      demandOption: true,
    })
    .option("auth", {
      alias: "a",
      description:
        'Base64-encoded Authorization header (e.g., "Basic username:api_token")',
      type: "string",
      demandOption: true,
    })
    .option("output", {
      alias: "o",
      description: "Output file path prefix (e.g., 'output' for output.pdf)",
      type: "string",
      default: "output",
    })
    .help()
    .alias("help", "h").argv;

  const { url, auth, output } = argv;

  const browser = await puppeteer.launch({ headless: false }); // Use headless: true for production
  const page = await browser.newPage();

  try {
    // Step 1: Set Authorization Header
    await page.setExtraHTTPHeaders({
      Authorization: auth,
      "X-Atlassian-Token": "no-check",
    });

    // Debug: Log failed requests
    page.on("requestfailed", (request) => {
      console.error(
        `Request failed: ${request.url()} - ${request.failure().errorText}`
      );
    });

    // Step 2: Navigate to the page
    console.log(`Navigating to URL: ${url}`);
    await page.goto(url, { waitUntil: "networkidle2" });

    // Debug: Log final URL
    console.log(`Final URL: ${page.url()}`);

    // Debug: Capture screenshot
    console.log("Capturing screenshot...");
    await page.screenshot({ path: "debug-screenshot.png", fullPage: true });

    // Step 3: Generate the PDF
    console.log("Generating PDF...");
    const pdfPath = `${output}.pdf`;
    await page.pdf({
      path: pdfPath,
      format: "A2",
      landscape: true,
      printBackground: true,
      margin: {
        top: "10mm",
        right: "10mm",
        bottom: "10mm",
        left: "10mm",
      },
    });
    console.log(`PDF saved as '${pdfPath}'`);
  } catch (err) {
    console.error("An error occurred:", err);
  } finally {
    await browser.close();
  }
})();
