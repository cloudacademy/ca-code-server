# ca-code-server

Builds a vanilla code-server image with the exceptoin of setting the app name fields to `ca-code-labs`

## Built-In Proxy

code-server has a built in proxy allowing you to access different ports within the container at the path:

```
/proxy/{port}
```

For example, running locally can reach port 8080 in the container at the following URL:

```
http://localhost:3000/proxy/8080
```
