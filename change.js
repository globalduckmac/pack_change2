const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { parseStringPromise } = require('xml2js');
const { exec } = require('child_process');
require('dotenv').config()


function runCommand(command, workingDir = __dirname) {

  console.log(command)

  return new Promise((resolve) => {
    const options = {};
    if (workingDir) {
      options.cwd = workingDir;
    }

    exec(command, options, (error, stdout, stderr) => {
      if (error) {
        resolve(error.code);
      } else {
        resolve(0);
      }
    });
  });
}



async function getPackageAttribute(filePath) {
  try {
    const xmlData = await fs.promises.readFile(filePath, 'utf-8');
    const result = await parseStringPromise(xmlData, { explicitRoot: false, explicitArray: false });

    if (result && result.$ && result.$.package) {
      return result.$.package;
    } else {
      throw new Error('Атрибут "package" не найден в теге <manifest>.');
    }
  } catch (err) {
    throw new Error(`Ошибка при обработке XML: ${err.message}`);
  }
}

function createReplacements(oldPackage, newPackage){

    const res = []
    res.push(
        { search: oldPackage, replace: newPackage }
    )
    res.push(
        { search: oldPackage.replaceAll('.', '/'), replace: newPackage.replaceAll('.', '/') }
    )
    return res
}

function processFile(filePath, replacements) {
  let content = fs.readFileSync(filePath, 'utf-8');
  let originalContent = content;

  for (const { search, replace } of replacements) {
    content = content.split(search).join(replace);
  }

  if (content !== originalContent) {
    fs.writeFileSync(filePath, content, 'utf-8');
    console.log(`Modified: ${filePath}`);
  }
}

function processDirectory(dir, replacements) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      processDirectory(fullPath, replacements);
    } else if (entry.isFile() && (fullPath.endsWith('.smali') || fullPath.endsWith('.xml'))) {
      processFile(fullPath, replacements);
    }
  }
}

async function filterLinesByRegex(filePath, regex) {
  const result = [];

  const fileStream = fs.createReadStream(filePath);
  const rl = readline.createInterface({
    input: fileStream,
    crlfDelay: Infinity
  });

  for await (const line of rl) {
    if (regex.test(line)) {
      result.push(line);
    }
  }

  return result;
}




async function main(args) {

    const packgeNameRegexp = /^(?:[a-zA-Z]+(?:\d*[a-zA-Z_]*)*)(?:\.[a-zA-Z]+(?:\d*[a-zA-Z_]*)*)+$/

    const apkPath = args[0]
    const packageListPath = args[1]

    const decodedApkPath = `${apkPath}.decoded`
    let workingDir = path.dirname(apkPath);


    const javaPath = process.env.JAVA_PATH
    const zipalignPath = process.env.ZIPALIGN_PATH
    const apksignerPath = process.env.APKSIGNER_PATH
    const keystorePath = path.join(workingDir, `${process.env.KEYSTORE_NAME}`)
    const keyAlias = process.env.KEY_ALIAS
    const keystorePassword = process.env.KEYSTORE_PASSWORD
    const keyPassword = process.env.KEY_PASSWORD


    const packages = await filterLinesByRegex(packageListPath, packgeNameRegexp)
    console.log('packages', packages)

    if(packages.length == 0){

        console.log('Error, package list is empty')
        return
    }

    let code = 0

    code = await runCommand(`${javaPath} -jar apktool.jar d -f -o ${decodedApkPath} ${apkPath}`, workingDir)
    console.log('code: ', code)


    for (let index = 0; index < packages.length; index++) {
        const newPackageName = packages[index];

        console.log('newPackageName', newPackageName)
        const newApkPath = path.join(workingDir, `${newPackageName}.apk`)
        const newAlignedApkPath = path.join(workingDir, `aligned_${newPackageName}.apk`)
        const newSignedApkPath = path.join(workingDir, `signed_${newPackageName}.apk`)


        let origPackageName = await getPackageAttribute(path.join(decodedApkPath, 'AndroidManifest.xml'))
        console.log('origPackageName: ', origPackageName)

        const replacements = createReplacements(origPackageName, newPackageName)
        processDirectory(decodedApkPath, replacements)

        code = await runCommand(`${javaPath} -jar apktool.jar b -o ${newApkPath} ${decodedApkPath}`, workingDir)
        console.log('code: ', code)

        code = await runCommand(`${zipalignPath} -v -p 4 ${newApkPath} ${newAlignedApkPath}`, workingDir)
        console.log('code: ', code)

        code = await runCommand(`${apksignerPath} sign --ks ${keystorePath} --ks-key-alias ${keyAlias} --ks-pass pass:${keystorePassword} --key-pass pass:${keyPassword} --out ${newSignedApkPath} ${newAlignedApkPath}`, workingDir)
        console.log('code: ', code)
        if(code == 0){
            fs.unlinkSync(`${newAlignedApkPath}`)        
        }
    }

    fs.rmSync(decodedApkPath, { recursive: true })
    
    console.log('Done!')
}

main(process.argv.slice(2));
