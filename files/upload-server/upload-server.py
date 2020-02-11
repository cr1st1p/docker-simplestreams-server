#!/usr/bin/env python3

# modified from https://github.com/pi314/hfs/blob/master/hfs/core.py

import argparse
import datetime
import mimetypes
import os
import re
import sys

from contextlib import suppress
from os.path import isdir, join
from shutil import rmtree

import bottle

PROJECT_ROOT = os.path.dirname(os.path.realpath(__file__))

bottle.TEMPLATE_PATH = [
    join(PROJECT_ROOT, 'html'),
]

BASE_DIR = PROJECT_ROOT
ALLOW_DELETES = False
ALLOW_OVERWRITES = False
ALLOW_CREATE_DIRS = True
DEBUG = False

flist_filters = {
    'hidden': lambda x: x.hidden,
    'shown': lambda x: not x.hidden,
    'file': lambda x: not x.isdir,
    'dir': lambda x: x.isdir,
}




class FileItem:
    def __init__(self, fpath):
        fpath = fpath if fpath else '.'
        fpath = re.sub(r'/+', '/', fpath).strip('/')
        if '/../' in fpath or fpath.startswith('../') or ('..' == fpath):
            raise bottle.HTTPError(status=403, body='Invalid path')
        
        fpath = '' if fpath in ['.', '..'] else fpath
        
        self.fpath = fpath

    @property
    def realpath(self):
        return join(BASE_DIR, self.fpath)

    @property
    def fname(self):
        return os.path.basename(self.fpath)

    @property
    def ftext(self):
        return self.fname + ('/' if self.isdir else '')

    @property
    def mtime(self):
        t = datetime.datetime.fromtimestamp(os.path.getmtime(self.realpath))
        return '{:04}/{:02}/{:02} {:02}:{:02}:{:02}'.format(
            t.year, t.month, t.day,
            t.hour, t.minute, t.second,
        )

    @property
    def size(self):
        return os.path.getsize(self.realpath)

    @property
    def hidden(self):
        return self.fname.startswith('.')

    @property
    def isdir(self):
        return isdir(self.realpath)

    @property
    def exists(self):
        return os.path.exists(self.realpath)

    def __repr__(self):
        return '<FileItem: "{}">'.format(self.ftext)

    @property
    def parent(self):
        return FileItem(os.path.dirname(self.fpath))

    @property
    def deletable(self):
        global ALLOW_DELETES
        if not ALLOW_DELETES:
            return False

        if len(self.fpath) == 0:
            return False

        return True


class DirectoryItem:
    def __init__(self, dname='', dpath=''):
        self.dname = dname
        self.dpath = dpath

    def __add__(self, dname):
        return DirectoryItem(dname, self.dpath + '/' + dname)

    def __repr__(self):
        return '<DirectoryItem: "{}">'.format(self.dpath)



def is_user_agent_curl():
    return bottle.request.get_header('User-Agent', default='').startswith('curl')


def is_client_denied(client_addr):
    return False
    

@bottle.route('/', method=('GET', 'POST'))
def root():
    return serve('.')


@bottle.route('/static/<urlpath:path>')
def static(urlpath):
    return bottle.static_file(urlpath, root=join(PROJECT_ROOT, 'static'))


@bottle.route('/<urlpath:path>', method=('GET', 'POST', 'DELETE'))
def serve(urlpath):
    target = FileItem(urlpath)
    global DEBUG
    global ALLOW_DELETES

    if DEBUG:
        print("DEBUG: urlpath: {} -> {} -> {} ".format(urlpath, target.fpath, target.realpath))

    bottle.request.get('REMOTE_ADDR')
    if is_client_denied(bottle.request.get('REMOTE_ADDR')):
        raise bottle.HTTPError(status=403, body='Permission denied')

    if bottle.request.method == 'GET':
        return (serve_dir if target.isdir else serve_file)(target)

    elif bottle.request.method == 'POST':
        if ALLOW_CREATE_DIRS or target.isdir:
            upload = bottle.request.files.getall('upload')
            if not upload:
                # client did not provide a file
                if DEBUG:
                    print("DEBUG: Upload: you did not a provide a file to upload - field name is 'upload'")

                return bottle.redirect('/{}'.format(urlpath))

            for f in upload:                
                fpath = get_uniq_fpath(join(target.fpath, f.raw_filename))
                if DEBUG:
                    print("DEBUG: upload file: {}".format(fpath))
                fileitem = FileItem(fpath)
                if fileitem.exists:
                    if DEBUG:
                        print("DEBUG: will remove file: {}".format(fileitem.realpath))

                    if not ALLOW_DELETES:
                        raise bottle.HTTPError(status=405, body='Deletion not permitted')

                    os.remove(fileitem.realpath)

                if ALLOW_CREATE_DIRS: 
                    d = os.path.dirname(fileitem.realpath)
                    if not isdir(d):
                        os.makedirs(d)
                if DEBUG:
                    print("DEBUG: will save file: {}".format(fileitem.realpath))
                f.save(fileitem.realpath)

        return bottle.redirect('/{}'.format(urlpath))

    elif bottle.request.method == 'DELETE':
        if not ALLOW_DELETES:
            raise bottle.HTTPError(status=405, body='Deletion not permitted')

        elif not target.exists:
            raise bottle.HTTPError(status=404, body='File "{}" does not exist'.format(target.fpath))

        elif target.isdir:
            with suppress(OSError):
                rmtree(target.realpath)

            return serve_dir(target.parent)

        else:
            os.remove(target.realpath)
            return serve_dir(target.parent)


@bottle.error(403)
@bottle.error(404)
@bottle.error(405)
def error_page(error):
    status = error.status
    reason = error.body
    if isinstance(status, int):
        status = '{} {}'.format(
                status,
                bottle.HTTP_CODES.get(status, bottle.HTTP_CODES[500])
        )

    if not is_user_agent_curl():
        return '<h1>Error: {}</h1><h2>{}</h2>'.format(status, reason)

    if reason:
        return 'Error: {}\n{}\n'.format(status, reason)

    return 'Error: {}\n'.format(status)


def serve_file(fileitem: FileItem):
    mimetype = mimetypes.guess_type(fileitem.realpath)[0]
    if mimetype is None:
        mimetype='application/octet-stream'

    global BASE_DIR
    target_file = bottle.static_file(
        fileitem.fpath,
        root=BASE_DIR,
        mimetype=mimetype
    )

    if target_file.status_code == 404:
        raise bottle.HTTPError(status=target_file.status, body='File "{}" does not exist'.format(fileitem.fpath))

    elif target_file.status_code >= 400:
        raise bottle.HTTPError(status=target_file.status)

    return target_file


def serve_dir(fileitem: FileItem):
    filters = bottle.request.urlparts.query.split('?')

    args = {
        'ancestors_dlist': get_ancestors_dlist(fileitem),
        'curdir': fileitem.fpath,
        'flist': get_flist(fileitem, filters),
        'host': bottle.request.urlparts.netloc,
        'pipe': 'pipe' in filters,
    }

    if is_user_agent_curl():
        return bottle.template('curl-listdir.html', **args)

    return bottle.template('listdir.html', **args)


def get_flist(fileitem: FileItem, filters):
    raw_flist = filter(
        lambda x: x.exists,
        map(
            lambda x: FileItem(join(fileitem.fpath, x)),
            os.listdir(fileitem.realpath)
        )
    )

    for f in filters:
        raw_flist = filter(
            flist_filters.get(f, lambda x: x),
            raw_flist,
        )

    return sorted(
        raw_flist,
        key=lambda x: x.isdir,
        reverse=True
    )


def get_ancestors_dlist(fileitem: FileItem):
    filepath = fileitem.fpath
    if filepath == '.':
        filepath = ''

    curdir_name_split = filepath.split('/')
    ancestors_dlist = []
    temp = DirectoryItem()
    for i in curdir_name_split:
        temp = temp + i
        ancestors_dlist.append(temp)

    return ancestors_dlist


def get_uniq_fpath(filepath):
    fitem = FileItem(filepath)
    if ALLOW_OVERWRITES or not fitem.exists:
        return fitem.fpath

    probing_number = 1
    root, ext = os.path.splitext(fitem.fpath)
    fitem = FileItem('{}-{}{}'.format(root, probing_number, ext))
    while fitem.exists:
        probing_number += 1
        fitem = FileItem('{}-{}{}'.format(root, probing_number, ext))

    return fitem.fpath


def main():
    print("\n\nFile Upload server starting...\n\n", flush=True)

    parser = argparse.ArgumentParser(
        description='Simple HTTP File Server',
        prog='upload-server')

    parser.add_argument('--port',
        help='The port this server should listen on',
        nargs='?', type=int, default=8000)

    parser.add_argument('--allow-delete', 
        help='Allow deletes',
        default=False, action='store_true')
    parser.add_argument('--debug', 
        help='Print debugging info',
        default=False, action='store_true')

    parser.add_argument('--allow-overwrite', 
        help='Allow overwrites',
        default=False, action='store_true')

    parser.add_argument('--base-dir', 
        help='Base directory to serve',
        type=str)

    args = parser.parse_args()

    if args.allow_delete:
        print('*** Notice: DELETE is allowed')
        global ALLOW_DELETES
        ALLOW_DELETES = True

    if args.allow_overwrite:
        global ALLOW_OVERWRITES
        ALLOW_OVERWRITES = True

    if args.debug:
        print('*** Notice: Debug messages enabled')
        global DEBUG
        DEBUG = True

    if args.base_dir:
        global BASE_DIR
        BASE_DIR = args.base_dir
        if not isdir(BASE_DIR):
            print("'{}' is not a directory".format(BASE_DIR))
            sys.exit(1)        

    print("BASE_DIR: ", BASE_DIR)

    bottle.run(host='0.0.0.0', port=args.port)


if __name__ == '__main__':
    main()

