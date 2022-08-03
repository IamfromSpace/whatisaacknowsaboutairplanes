let hostedZone =
      \(domainName : Text) ->
        { Type = "AWS::Route53::HostedZone", Properties.Name = domainName }

let cert =
      \(hostedZoneLogicalId : Text) ->
      \(domainName : Text) ->
        { Type = "AWS::CertificateManager::Certificate"
        , Properties =
          { DomainName = domainName
          , DomainValidationOptions =
            [ { DomainName = domainName
              , HostedZoneId =
                [ { mapKey = "Ref", mapValue = hostedZoneLogicalId } ]
              }
            ]
          , ValidationMethod = "DNS"
          }
        }

let bucket = { Type = "AWS::S3::Bucket", Properties = {=} }

let JoinItem =
    --Some type checker Appeasement.  F shold really be much more expressive.
      < T : Text | F : List { mapKey : Text, mapValue : List Text } >

let JoinData = < Delimiter : Text | Items : List JoinItem >

let bucketPolicy =
      \(bucketLogicalId : Text) ->
      \(originAccessIdentityLogicalId : Text) ->
        { Type = "AWS::S3::BucketPolicy"
        , Properties =
          { Bucket = [ { mapKey = "Ref", mapValue = bucketLogicalId } ]
          , PolicyDocument =
            { Version = "2012-10-17"
            , Statement =
              [ { Action = [ "s3:GetObject" ]
                , Effect = "Allow"
                , Resource =
                  [ { mapKey = "Fn::Join"
                    , mapValue =
                      [ JoinData.Delimiter ""
                      , JoinData.Items
                          [ JoinItem.F
                              [ { mapKey = "Fn::GetAtt"
                                , mapValue = [ bucketLogicalId, "Arn" ]
                                }
                              ]
                          , JoinItem.T "/*"
                          ]
                      ]
                    }
                  ]
                , Principal.CanonicalUser
                  =
                  [ { mapKey = "Fn::GetAtt"
                    , mapValue =
                      [ originAccessIdentityLogicalId, "S3CanonicalUserId" ]
                    }
                  ]
                }
              ]
            }
          }
        }

let oai =
      \(domainName : Text) ->
        { Type = "AWS::CloudFront::CloudFrontOriginAccessIdentity"
        , Properties.CloudFrontOriginAccessIdentityConfig.Comment
          = "For ${domainName}"
        }

let distro =
      \(originAccessIdentityLogicalId : Text) ->
      \(certificateLogicalId : Text) ->
      \(bucketLogicalId : Text) ->
      \(domainName : Text) ->
        let originId = "myS3Origin"

        in  { Type = "AWS::CloudFront::Distribution"
            , Properties.DistributionConfig
              =
              { Origins =
                [ { DomainName =
                    [ { mapKey = "Fn::GetAtt"
                      , mapValue = [ bucketLogicalId, "DomainName" ]
                      }
                    ]
                  , Id = originId
                  , S3OriginConfig.OriginAccessIdentity
                    =
                    [ { mapKey = "Fn::Sub"
                      , mapValue =
                          "origin-access-identity/cloudfront/\${${originAccessIdentityLogicalId}}"
                      }
                    ]
                  }
                ]
              , Enabled = "true"
              , Comment = "Some comment"
              , DefaultRootObject = "index.html"
              , Aliases = [ domainName ]
              , DefaultCacheBehavior =
                { AllowedMethods = [ "GET", "HEAD", "OPTIONS" ]
                , TargetOriginId = originId
                , ForwardedValues =
                  { QueryString = "false", Cookies.Forward = "none" }
                , ViewerProtocolPolicy = "redirect-to-https"
                }
              , HttpVersion = "http2"
              , PriceClass = "PriceClass_200"
              , ViewerCertificate =
                { AcmCertificateArn =
                  [ { mapKey = "Ref", mapValue = certificateLogicalId } ]
                , MinimumProtocolVersion = "TLSv1.2_2021"
                , SslSupportMethod = "sni-only"
                }
              }
            }

let dnsRecord =
      \(hostedZoneLogicalId : Text) ->
      \(distributionLogicalId : Text) ->
      \(domainName : Text) ->
        { Type = "AWS::Route53::RecordSet"
        , Properties =
          { AliasTarget =
            { DNSName =
              [ { mapKey = "Fn::GetAtt"
                , mapValue = [ distributionLogicalId, "DomainName" ]
                }
              ]
            , HostedZoneId = "Z2FDTNDATAQYW2"
            }
          , HostedZoneId =
            [ { mapKey = "Ref", mapValue = hostedZoneLogicalId } ]
          , Name = domainName
          , Type = "A"
          }
        }

in  \(domainName : Text) ->
      { AWSTemplateFormatVersion = "2010-09-09"
      , Resources =
        { Distribution =
            -- Note that by doing this all together, the cert _must_ be in
            -- us-east-1 to work with Cloudfront
            distro "OriginAccessIdentity" "Certificate" "Bucket" domainName
        , HostedZone = hostedZone domainName
        , Bucket = bucket
        , BucketPolicy = bucketPolicy "Bucket" "OriginAccessIdentity"
        , OriginAccessIdentity = oai domainName
        , Certificate = cert "HostedZone" domainName
        , DnsRecord = dnsRecord "HostedZone" "Distribution" domainName
        }
      }
