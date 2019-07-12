#!/usr/bin/env bash
URL=$1
if [[ -n $2 ]]; then
    GIT_OAUTH_TOKEN=$2
elif [[ -f ".githubtoken" ]]; then
    GIT_OAUTH_TOKEN=$(cat .githubtoken)
else
    echo "Please provide github oauth token as a parameter or place it in a file called .githubtoken in the root of this repo"
    exit 1
fi
ORG=AndroidDumps #for orgs support, here can write your org name
axel -a -n64 ${URL:?} #download rom
IFS='?'
FILE=${URL##*/}
EXTENSION=${URL##*.}
UNZIP_DIR=${FILE/.$EXTENSION/}
read -ra CLEANED <<< "${FILE}" #Cleanup query strings if any
FILE=${CLEANED[0]}

if [[ "${EXTENSION}" == "tgz" ]]; then
    tar xf ${FILE}
    cd */images
else
    if [[ -f "${FILE}" ]]; then
        7z e ${FILE} -o${UNZIP_DIR}
    else
        7z e * -o${UNZIP_DIR}
    fi

    cd ${UNZIP_DIR} || exit
    files=$(ls *.zip)
    if [[ -f "${files}" ]] && [[ $(echo ${files} | wc -l) -eq 1 ]] && [[ "${files}" != "compatibility.zip" ]]; then
        unzip ${files}
    fi

    if [[ -f "payload.bin" ]]; then
        if [[ ! -d "${HOME}/extract_android_ota_payload" ]]; then
            cd
            git clone https://github.com/cyxx/extract_android_ota_payload
            cd -
        fi
        python2 ~/extract_android_ota_payload/extract_android_ota_payload.py payload.bin
    fi

fi

rm -fv $OLDPWD/*.zip

if [[ -f "servicefile.xml" ]]; then # For Moto firmwares only
    if [[ -f "system.img_sparsechunk.0" ]]; then
            ../simg2img system.img_sparsechunk* system.img.tmp
            offset=`LANG=C grep -aobP -m1 '\x53\xEF' system.img.tmp | head -1 | awk '{print $1 - 1080}'`
            if [[ "$offset" == 128055 ]]; then
                offset=131072
            fi
            dd if=system.img.tmp of=system.img ibs=$offset skip=1
            rm system.img_sparsechunk*
            rm system.img.tmp
    fi
    if [[ -f "vendor.img" ]]; then
            mv vendor.img vendor.img.tmp
            ../simg2img vendor.img.tmp vendor.unsp
            offset=`LANG=C grep -aobP -m1 '\x53\xEF' vendor.unsp | head -1 | awk '{print $1 - 1080}'`
            if [[ "$offset" == 128055 ]]; then
                offset=131072
            fi
            dd if=vendor.unsp of=vendor.img ibs=$offset skip=1
            rm vendor.img.tmp
            rm vendor.uns
    fi
    if [[ -f "vendor.img_sparsechunk.0" ]]; then
            ../simg2img vendor.img_sparsechunk* vendor.img.tmp
            offset=`LANG=C grep -aobP -m1 '\x53\xEF' vendor.img.tmp | head -1 | awk '{print $1 - 1080}'`
            if [[ "$offset" == 128055 ]]; then
                offset=131072
            fi
            dd if=vendor.img.tmp of=vendor.img ibs=$offset skip=1
            rm vendor.img_sparsechunk*
            rm vendor.img.tmp
    fi
    mv oem.img oem.img.tmp
    ../simg2img oem.img.tmp oem.img
    ../simg2img NON-HLOS.bin modem.img
fi

for p in system vendor cust odm oem; do
    brotli -d $p.new.dat.br &>/dev/null ; #extract br
    cat $p.new.dat.{0..999} 2>/dev/null >> $p.new.dat #merge split Vivo(?) sdat
    ../sdat2img.py $p.{transfer.list,new.dat,img} &>/dev/null #convert sdat to img
    mkdir $p\_ || rm -rf $p/*
    echo $p 'extracted'
    sudo mount -t ext4 -o loop $p.img $p\_ &>/dev/null #mount imgs
    sudo chown $(whoami) $p\_/ -R
    sudo chmod -R u+rwX $p\_/
done

mkdir modem_
for modem in {firmware-update/,}{modem.img,NON-HLOS.bin}; do
    sudo mount -t vfat -o loop $modem modem_/ && break
done

if [[ ! -d "${HOME}/extract-dtb" ]]; then
    cd
    git clone https://github.com/PabloCastellano/extract-dtb
    cd -
fi
python3 ~/extract-dtb/extract-dtb.py ./boot.img -o ./bootimg > /dev/null # Extract boot
python3 ~/extract-dtb/extract-dtb.py ./dtbo.img -o ./dtbo > /dev/null # Extract dtbo
echo 'boot extracted'
for p in system vendor modem cust odm oem; do
        sudo cp -r $p\_ $p/ #copy images
        echo $p 'copied'
        sudo umount $p\_ &>/dev/null #unmount
        rm -rf $p\_
done

#copy file names
sudo chown $(whoami) * -R ; chmod -R u+rwX * #ensure final permissions
find system/ -type f -exec echo {} >> allfiles.txt \;
find vendor/ -type f -exec echo {} >> allfiles.txt \;
find bootimg/ -type f -exec echo {} >> allfiles.txt \;
find dtbo/ -type f -exec echo {} >> allfiles.txt \;
find modem/ -type f -exec echo {} >> allfiles.txt \;
find cust/ -type f -exec echo {} >> allfiles.txt \;
find odm/ -type f -exec echo {} >> allfiles.txt \;
find oem/ -type f -exec echo {} >> allfiles.txt \;
sort allfiles.txt > all_files.txt
rm allfiles.txt
rm *.dat *.list *.br system.img vendor.img 2>/dev/null #remove all compressed files

ls system/build.prop 2>/dev/null || ls system/system/build.prop 2>/dev/null || { echo "No system build.prop found, pushing cancelled!" && exit ;}

flavor=$(grep -oP "(?<=^ro.build.flavor=).*" -hs {system,system/system,vendor}/build.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.vendor.build.flavor=).*" -hs vendor/build.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.system.build.flavor=).*" -hs {system,system/system}/build.prop)
[[ -z "${flavor}" ]] && flavor=$(grep -oP "(?<=^ro.build.type=).*" -hs {system,system/system}/build.prop)
release=$(grep -oP "(?<=^ro.build.version.release=).*" -hs {system,system/system,vendor}/build.prop)
[[ -z "${release}" ]] && release=$(grep -oP "(?<=^ro.vendor.build.version.release=).*" -hs vendor/build.prop)
[[ -z "${release}" ]] && release=$(grep -oP "(?<=^ro.system.build.version.release=).*" -hs {system,system/system}/build.prop)
id=$(grep -oP "(?<=^ro.build.id=).*" -hs {system,system/system,vendor}/build.prop)
[[ -z "${id}" ]] && id=$(grep -oP "(?<=^ro.vendor.build.id=).*" -hs vendor/build.prop)
[[ -z "${id}" ]] && id=$(grep -oP "(?<=^ro.system.build.id=).*" -hs {system,system/system}/build.prop)
incremental=$(grep -oP "(?<=^ro.build.version.incremental=).*" -hs {system,system/system,vendor}/build.prop)
[[ -z "${incremental}" ]] && incremental=$(grep -oP "(?<=^ro.vendor.build.version.incremental=).*" -hs vendor/build.prop)
[[ -z "${incremental}" ]] && incremental=$(grep -oP "(?<=^ro.system.build.version.incremental=).*" -hs {system,system/system}/build.prop)
tags=$(grep -oP "(?<=^ro.build.tags=).*" -hs {system,system/system,vendor}/build.prop)
[[ -z "${tags}" ]] && tags=$(grep -oP "(?<=^ro.vendor.build.tags=).*" -hs vendor/build.prop)
[[ -z "${tags}" ]] && tags=$(grep -oP "(?<=^ro.system.build.tags=).*" -hs {system,system/system}/build.prop)
fingerprint=$(grep -oP "(?<=^ro.build.fingerprint=).*" -hs {system,system/system,vendor}/build.prop)
[[ -z "${fingerprint}" ]] && fingerprint=$(grep -oP "(?<=^ro.vendor.build.fingerprint=).*" -hs vendor/build.prop)
[[ -z "${fingerprint}" ]] && fingerprint=$(grep -oP "(?<=^ro.system.build.fingerprint=).*" -hs {system,system/system}/build.prop)
brand=$(grep -oP "(?<=^ro.product.brand=).*" -hs {system,system/system,vendor}/build.prop)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.vendor.brand=).*" -hs vendor/build.prop)
[[ -z "${brand}" ]] && brand=$(grep -oP "(?<=^ro.product.system.brand=).*" -hs {system,system/system}/build.prop)
[[ -z "${brand}" ]] && brand=$(echo $fingerprint | cut -d / -f1 )
codename=$(grep -oP "(?<=^ro.product.device=).*" -hs {system,system/system,vendor}/build.prop)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.vendor.device=).*" -hs vendor/build.prop)
[[ -z "${codename}" ]] && codename=$(grep -oP "(?<=^ro.product.system.device=).*" -hs {system,system/system}/build.prop)
[[ -z "${codename}" ]] && codename=$(echo $fingerprint | cut -d / -f3 | cut -d : -f1 )
description=$(grep -oP "(?<=^ro.build.description=).*" -hs {system,system/system,vendor}/build.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.vendor.build.description=).*" -hs vendor/build.prop)
[[ -z "${description}" ]] && description=$(grep -oP "(?<=^ro.system.build.description=).*" -hs {system,system/system}/build.prop)
[[ -z "${description}" ]] && description="$flavor $release $id $incremental $tags"
branch=$(echo $description | tr ' ' '-')
repo=$(echo $brand\_$codename\_dump | tr '[:upper:]' '[:lower:]')

user=TadiT7 #set user for github
git init
git config user.name Tadi
git config user.email TadiT7@github.com
git checkout -b $branch
find -size +97M -printf '%P\n' -o -name *sensetime* -printf '%P\n' -o -name *.lic -printf '%P\n' > .gitignore
git add --all
git reset mkbootimg_tools/ META-INF/ file_contexts.bin

curl -s -X POST -H "Authorization: token ${GIT_OAUTH_TOKEN}" -d '{ "name": "'"$repo"'" }' "https://api.github.com/orgs/${ORG}/repos" #create new repo
git remote add origin https://github.com/$ORG/${repo,,}.git
git commit -asm "Add ${description}"
git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ||

(git update-ref -d HEAD ; git reset system/ vendor/ ;
git checkout -b $branch ;
git commit -asm "Add extras for ${description}" ;
git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;
git add vendor/ ;
git commit -asm "Add vendor for ${description}" ;
git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;
git add system/system/app/ system/system/priv-app/ || git add system/app/ system/priv-app/ ;
git commit -asm "Add apps for ${description}" ;
git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;
git add system/ ;
git commit -asm "Add system for ${description}" ;
git push https://$GIT_OAUTH_TOKEN@github.com/$ORG/${repo,,}.git $branch ;)
