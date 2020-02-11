## Simplestreams server

This brings together project https://github.com/Avature/lxd-image-server (well, from my fork, https://github.com/cr1st1p/lxd-image-server, branch *import-metadata* , since it contains various fixes + improvements) + a file uploader server, all, in one.

It creates a docker image out of those parts. 

You should run that image behind a SSL terminating proxy - LXD for example accepts only **https** simplestream repositories. For example, run this inside a Kubernetes cluster.

You will need to mount a volume into directory ```/var/www/simplestreams```



### What does it do??

Simplestream is a 'protocol' (description) for describing what virtual machine images exist on a http(s) repository.

It mainly consists on serving, besides the actual machine images content, 2 files:

- streams/v1/index.json
- streams/v1/images.json

```images.json``` contains a list of all the virtual machine images, with various information about them.

What the *lxd-image-server* does (but it is not related strictly to lxd), is to automatically update the images.json file when it detects new files uploaded. Well, it does some external repositories updates as well, but that's a different story.

This image also adds a simple web server file upload feature, so it is more of an integrated solution.

You should protect access to this server (via the SSL terminating proxy)

Please check the section *This is the structure the simplestreams server needs to have.* at https://github.com/Avature/lxd-image-server/blob/master/README.md to understand how the images you upload should be named and in which directories they should end.

Code will set various fields based on that directory layout! Changes in the particular forked repository also allows you to upload a ```metadata.json``` with which you can override:

- os
- release_title
- aliases (an array)



### Configuration

As usual, via environment variables:

- DEBUG : will make programs output more things
- ALLOW_OVERWRITES: if non empty, it will allow you to update files, else, it will create them with a changed filename
- ALLOW_DELETES: if non empty, it allows you to delete files via http method DELETE



### Use as a remote for LXD

```shell
lxc remote add my_remote https://...your_server
lxc image list my_remote:
```



### How to upload files

Obtain the image(s). Example with lxd:

```shell
mkdir -p /tmp/img
cd /tmp/img
lxc image list
lxc image export 9e7158fc0683
ls -l
```

We have 2 files (in this case - but if you export an image obtained from a container, things are more complicated): ```9e7158fc0683d41......squashfs``` and ```meta-9e7158fc0683d41.....tar.xz``` (digits removed)

This is an ubuntu image, architecture amd64.

```shell
product=ubuntu
release=xenial
arch=amd64
box=default
remote=https://your_install.com
# you MUST obey the date format
upload_date=$(date '+%Y%m%d_%H:%M')

dir="$product/$release/$arch/$box/$upload_date"

# HERE, you might first want to edit a metadata.json and upload it
# ...

curl "-Fupload=@meta-9e7158fc0683d41.....tar.xz;filename=$dir/lxd.tar.xz" "$remote/images/"
curl "-Fupload=@9e7158fc0683d41.....squashfs;filename=$dir/rootfs.squashfs" "$remote/images/"

# check, after seconds (code needs to compute checksums), the presence in:
curl -v "$remote/streams/v1/images.json"
# or, via lxc client:
lxc image list my_remote:
```



For an image created from a container, when you do an ```lxc image export fingerprint``` you will obtain a single TAR file. This one contains both metadata and the image content itself. You'll have to manually create an lxd.tar.xz file out of it, without the rootfs/ directory, and a root.tar.xz with the content from rootfs/ 

