#!/usr/bin/env ruby

require 'trollop'
require 'patron'
require 'yaml'

opts=Trollop::options do
  opt :config_file, "Configuration file", :short=>'f', :default=>"/etc/elastichosts-api.yml"
  opt :zone, "Availability zone (overrides config file)", :type=>String
  opt :uri, "Elastichosts URI endpoint (overrides config file)", :type=>String
  opt :verbose, "Show progress"
  # we default to a low compression level because we don't think there's
  # much gain to be had from compressing full parts of the disk, and
  # even gzip -1 can find runs of zeroes
  opt :compression, "Compression level 1-9 (1=faster, 9=smaller)",
  :type => :int,:default=>2
  opt :uuid, "Destination drive UUID (omit to create a new drive)",:type=>String
  opt :debug1, "Show grisly details (not pretty, exposes secret information)"
end

if File.exist?(f=opts[:config_file]) then
  preferences=YAML.load_file f
  if p=preferences['zone'] then opts[:zone]||=p end
  if p=preferences[opts[:zone]]['uri'] then opts[:uri]||=p end
  if p=preferences[opts[:zone]]['uuid'] then $ehuser=p end
  if p=preferences[opts[:zone]]['key'] then $ehpass=p end
end
opts[:zone]||='lon-p'
opts[:uri]||='https://api-lon-p.elastichosts.com:443/'

if e=ENV['EHAUTH']
  $ehuser,$ehpass=e.split(/:/)
end

unless $ehpass && $ehuser
  raise "No API credentials set in either #{opts[:config_file]} or \$EHAUTH"
end

class Image
  attr_accessor :local_name,:local_bytes,:local_zipped
  # we upload the image gzipped and then perform an API call to unzip when
  # done.  This is the UID of the gzipped temporary image
  attr_accessor :zipped_uuid
  # and this is the real drive
  attr_accessor :uuid
  def initialize(n)
    @local_name=n
    @local_bytes=File.stat(n).size
    @local_zipped=true
    @sem=Mutex.new
  end
  def basename 
    File.basename(@local_name)
  end
end

def parse_response_body(s) 
  Hash[s.split(/\n/).map {|l| k,v=l.split; [k.to_sym,v] }]
end

$chunk=1*1024*1024; 
#$chunk=4*1024;

begin
  i=Image.new(ARGV[0])

  conn = Patron::Session.new
  conn.base_url=opts[:uri]
  conn.username=$ehuser
  conn.password=$ehpass
  conn.timeout=30
#  warn opts
#  exit 0
  if opts[:debug1] then
    warn "engaging debug mode"
    class << conn
      def post(url,body,headers)
        warn [:post,url,(body.length>400) ? "#{body.length} bytes" : body]
        response=super
        warn [:response,response.status_line,response.body]
        return response
      end
    end
    opts[:verbose]=true
  end
  opts[:verbose] and warn "Uploading image #{i.local_name}"

  headers={'accept'=>'*/*',
    'connection'=>'close',
    'content-type'=>'text/plain'
  }

  r=conn.post('drives/create',
              "name #{i.basename}_zip\nsize #{i.local_bytes}\nclaim:type exclusive",
              headers)
  ret=parse_response_body(r.body)
  i.zipped_uuid=ret[:drive]
  if i.zipped_uuid then
    opts[:verbose] and warn "created temporary image drive #{i.zipped_uuid}"
  else
    raise "Server returned \"#{r.status_line}\" - drive creation failed"
  end
  offset=0
  IO.popen("/bin/gzip -c -#{opts[:compression]} #{i.local_name}|dd obs=4M 2>/dev/null","r") do |f|
    finished = false
    while not finished
      begin
        bytes=f.sysread($chunk)
        opts[:verbose] and $stderr.print "."
        r=conn.post("drives/#{i.zipped_uuid}/write/#{offset}",bytes,{
                      'content-type'=>'application/octet-stream'
                    })
        unless r.status==204
          raise "#{r.status_line} at offset #{offset}"
        end
        offset+=bytes.length
      rescue EOFError => e
        finished = true
      end
    end
  end

  r=conn.post("drives/#{i.zipped_uuid}/set", "size #{offset}", headers)

  if i.uuid then
    opts[:verbose] and warn "unzipping to existing drive #{i.uuid}"
  else
    r=conn.post('drives/create',
                "name #{i.basename}\nsize #{i.local_bytes}\nclaim:type exclusive",
                headers)
    ret=parse_response_body(r.body)
    i.uuid=ret[:drive]
    opts[:verbose] and warn "created final image drive #{i.uuid}"
  end

  r=conn.post("drives/#{i.uuid}/image/#{i.zipped_uuid}/gunzip",'',headers)

  finished = false
  while not finished do
    r=conn.get("drives/#{i.uuid}/info")
    ret=parse_response_body(r.body)
    if r=ret[:imaging] then
      opts[:verbose] and warn "unzipping #{r}"
      sleep 1
    else
      opts[:verbose] and warn "unzipping finished"
      finished=1
    end
  end
end
