$JsonXPathConfigString = @"
{
    "title": "//*/h1",
    "VisibleAPIs": {
        "_xpath": "//a[(@class='list-group-item')]",
        "APIName": ".//h3",
        "APIVersion": ".//p//code//span[normalize-space()][2]",
        "APIDescription": ".//p[(@class='list-group-item-text')]"
    }
}
"@

$JsonXPathConfigString = @"
{
    "title": "//*[@id=\"app_mountpoint\"]/header/div/div[1]/div[1]/a/span[1]"
}
"@


$JsonXPathConfigString = @"
{
    "title": "//*/h1",
    "MenuItems": {
        "_xpath": "//*[@id=\"app_mountpoint\"]/header/div/div[1]",
        "MenuItem": ".//div/a/span"
    }
}
"@
Get-SiteAsJson -Url 'https://reelgood.com/' -XPathJsonConfigString $JsonXPathConfigString