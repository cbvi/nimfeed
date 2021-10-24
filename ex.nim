import parsexml, httpclient

type
    FeedError = object of CatchableError

    Guid = distinct string

    FeedType = enum
        RssFeed
        AtomFeed

    FeedStream = object
        x : XmlParser
        t : FeedType

    FeedItem = ref object
        title : string
        content : string
        link : string
        guid : Guid
        author : string
        categories : seq[string]

using
    fs: var FeedStream

proc determineFeedType(fs): FeedType =
    while true:
        fs.x.next()
        case fs.x.kind
            of xmlElementOpen, xmlElementStart:
                case fs.x.elementName
                of "rss":
                    return RssFeed
                of "feed":
                    return AtomFeed
            of xmlEof:
                raise newException(FeedError,
                    "Could not determine feed type")
            else:
                discard
        ;
    ;
;

proc openFeed*(url : string): FeedStream =
    try:
        let client = newHttpClient()
        let res = client.get(url)
        open(result.x, res.bodyStream, url)
    except Exception as err:
        raise newException(FeedError,
            "Could not read feed " & url & " :" & err.msg)
    ;

    result.t = determineFeedType(result)
;

proc readText(fs): string =
    while true:
        fs.x.next()
        case fs.x.kind
            of xmlCharData, xmlWhitespace, xmlCData:
                result.add(fs.x.charData)
            of xmlEntity:
                result.add(fs.x.entityName)
            else:
                break
        ;
    ;
;

proc parseRssItem(fs): FeedItem =
    assert(fs.t == RssFeed)
    new(result)
    while true:
        fs.x.next()
        case fs.x.kind
            of xmlElementStart, xmlElementOpen:
                case fs.x.elementName
                    of "title":
                        result.title = readText(fs)
                    of "description":
                        if result.content.len == 0:
                            result.content = readText(fs)
                    of "content:decoded":
                        result.content = readText(fs)
                    of "guid":
                        result.guid = Guid(readText(fs))
                    of "link":
                        result.link = readText(fs)
                    of "dc:creator":
                        result.author = readText(fs)
                    of "category":
                        result.categories.add(readText(fs))
                    else:
                        discard
                ;
            of xmlElementEnd:
                if fs.x.elementName == "item":
                    break
            of xmlEof:
                raise newException(FeedError,
                    "Unexpected EOF while parsing item")
            else:
                discard
        ;
    ;
;

proc parseAtomItem(fs): FeedItem =
    assert(fs.t == AtomFeed)
    new(result)
    while true:
        fs.x.next()
        case fs.x.kind
            of xmlElementStart, xmlElementOpen:
                case fs.x.elementName
                of "title":
                    result.title = readText(fs)
                of "content":
                    result.content = readText(fs)
                of "id":
                    result.guid = Guid(readText(fs))
                of "link":
                    while true:
                        fs.x.next()
                        case fs.x.kind
                            of xmlAttribute:
                                if fs.x.attrKey == "href":
                                    result.link = fs.x.attrValue
                            of xmlElementClose:
                                break
                            else:
                                discard
                        ;
                    ;
                of "author":
                    while true:
                        fs.x.next()
                        case fs.x.kind
                            of xmlElementStart, xmlElementOpen:
                                if fs.x.elementName == "name":
                                    result.author = readText(fs)
                                    break
                            of xmlElementEnd:
                                if fs.x.elementName == "author":
                                    break
                            else:
                                discard
                        ;
                    ;
                else:
                    discard
            of xmlElementEnd:
                if fs.x.elementName == "entry":
                    break
            of xmlEof:
                raise newException(FeedError,
                    "Unexpected EOF while parsing entry")
            else:
                discard
        ;
    ;
;

proc nextRssItem(fs): FeedItem =
    assert(fs.t == RssFeed)
    while true:
        fs.x.next()
        case fs.x.kind
            of xmlElementStart, xmlElementOpen:
                if fs.x.elementName == "item":
                    return parseRssItem(fs)
            of xmlEof:
                return nil
            else:
                discard
        ;
    ;
;

proc nextAtomItem(fs): FeedItem =
    assert(fs.t == AtomFeed)
    while true:
        fs.x.next()
        case fs.x.kind
            of xmlElementStart, xmlElementOpen:
                if fs.x.elementName == "entry":
                    return parseAtomItem(fs)
            of xmlEof:
                return nil
            else:
                discard
        ;
    ;
;

proc nextItem(fs): FeedItem =
    result = case fs.t
        of RssFeed:
            nextRssItem(fs)
        of AtomFeed:
            nextAtomItem(fs)
    ;
;

var fs : FeedStream
 
try:
    fs = openFeed("https://www.dragonflydigest.com/feed")
except Exception as e:
    quit("Reading feed failed: " & e.msg)
;

while true:
    try:
        let item = nextItem(fs)
        if item.isNil: break
        echo item.title, " (", item.link, ")"
    except Exception as e:
        quit("Error reading item: " & e.msg)
    ;
;

fs.x.close()
